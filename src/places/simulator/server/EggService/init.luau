--!strict
-- EggService (Simulator only, concept 7.9, ADR 0003, ADR 0013): buying and hatching eggs at the
-- egg stations. The rules are in the pure EggCore; this file wires them to the stations,
-- CurrencyService, PetService, Net, the pop-ups and the Studio switches.
--
-- A client sends `EggHatch()` without arguments. The server finds the open station within reach
-- of the character, spends Formulas.Pets.eggPrice(egg) through CurrencyService, rolls the rarity
-- with Rng and Config.Pets.Odds, and adds the pet through PetService. Not an immediate save
-- (ADR 0003): the pet lands with the next autosave or the leave save, together with the spend.
--
-- Every server writes the player attribute `EggLastHatch` = "<uid>:<kind>" after a hatch (the
-- client shows the reveal from it) and shows the "New Pet!" pop-up. Studio at PlaceId 0 adds
-- diagnostics and switches (ADR 0013).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EggsConfig = require(Config:WaitForChild("Eggs")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local UiConfig = require(Config:WaitForChild("Ui")) :: any
local ZonesConfig = require(Config:WaitForChild("Zones")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local PetCatalogue = require(Shared:WaitForChild("PetCatalogue")) :: any
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))
local PromptSpec = require(Shared:WaitForChild("Prompts"):WaitForChild("PromptSpec"))
local Rarity = require(Shared:WaitForChild("Rarity")) :: any
local Rng = require(Shared:WaitForChild("Rng")) :: any

local EggCore = require(script:WaitForChild("EggCore"))
local EggStations = require(script:WaitForChild("EggStations"))

local Server = script.Parent.Parent
local Services = Server:WaitForChild("Services")
local CurrencyService = require(Services:WaitForChild("CurrencyService"))
local NetService = require(Services:WaitForChild("NetService"))
local PopupService = require(Services:WaitForChild("PopupService"))
local PetService = require(Server:WaitForChild("SocialServices"):WaitForChild("PetService")) :: any

local REMOTE = "EggHatch"
local REMOTE_REASON = "Remote"
local STUDIO_REASON = "StudioSwitch"
local LAST_HATCH = "EggLastHatch"
local HATCHED_POPUP = "PetHatched"
local FULL_POPUP = "PetInventoryFull"

-- Studio-only switches on ServerScriptService (ADR 0013). The target is PetService's.
local TARGET_SWITCH = "PetTargetUserId"
local FORCE_SWITCH = "EggForceRarity"
local PURCHASE_SWITCH = "EggPurchase"
local GEOMETRY_SWITCH = "EggStationTestGeometry"
local LAST_ROLL = "EggLastRoll"
local REFUSALS = "EggRefusals"
local MAX_REPEAT = 10

-- Mirrors EggCore.Event (types of WaitForChild requires are not visible here).
type Event = {
	kind: "Hatched" | "Refused",
	userId: number,
	egg: number?,
	rarity: string?,
	pet: string?,
	uid: string?,
	price: number?,
	forced: boolean?,
	reason: string,
	refusal: string?,
}

local EggService = {}

local isStudio = RunService:IsStudio()
local studioTools = isStudio and game.PlaceId == 0
local started = false

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[EggService] {message}`)
	elseif isStudio then
		print(`[EggService] {message}`)
	end
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- Studio only: the EggForceRarity switch, when it holds a rarity id. Anything else rolls.
local function forcedRarity(): string?
	if not studioTools then
		return nil
	end
	local value = ServerScriptService:GetAttribute(FORCE_SWITCH)
	if type(value) == "string" and value ~= "" and Rarity.isRarity(value) then
		return value
	end
	return nil
end

local core = EggCore.new({
	config = EggsConfig,
	catalogue = PetCatalogue,
	eggCount = Formulas.Pets.eggCount,
	eggPrice = Formulas.Pets.eggPrice,
	eggOdds = Rng.eggOdds,
	pick = Rng.pick,
	generator = Rng.new(),
	now = os.clock,
	forcedRarity = forcedRarity,
	hasRoom = function(userId: number): (boolean, string?)
		local player = playerOf(userId)
		if player == nil then
			return false, "NotLoaded"
		end
		return PetService.HasRoom(player)
	end,
	addPet = function(userId: number, kind: string, reason: string): (boolean, string)
		local player = playerOf(userId)
		if player == nil then
			return false, "NotLoaded"
		end
		return PetService.AddPet(player, kind, reason)
	end,
	spendCoins = function(userId: number, amount: number, reason: string): (boolean, any)
		local player = playerOf(userId)
		if player == nil then
			return false, "NotLoaded"
		end
		return CurrencyService.SpendCoins(player, amount, reason)
	end,
	log = log,
})

-- Every server: the reveal attribute and the pop-ups.
local function onEvent(event: Event)
	local player = playerOf(event.userId)
	if player == nil then
		return
	end
	if event.kind == "Hatched" then
		player:SetAttribute(LAST_HATCH, `{event.uid}:{event.pet}`)
		PopupService.show(player, HATCHED_POPUP)
	elseif event.refusal == "InventoryFull" then
		PopupService.show(player, FULL_POPUP)
	end
end

local function describe(event: Event): string
	local egg = if event.egg then `egg {event.egg}` else "egg ?"
	local price = if event.price then ` price={event.price}` else ""
	if event.kind == "Refused" then
		return `{egg} {event.reason} refused: {event.refusal}{price}`
	end
	return `{egg} {event.reason} {event.rarity} -> {event.pet} uid={event.uid}{price} forced={event.forced}`
end

local function onStudioEvent(event: Event)
	local player = playerOf(event.userId)
	local text = describe(event)
	print(`[EggService] {if player then player.Name else "?"} ({event.userId}) {text}`)
	if player == nil then
		return
	end
	player:SetAttribute(LAST_ROLL, text)
	if event.kind == "Refused" then
		player:SetAttribute(REFUSALS, ((player:GetAttribute(REFUSALS) :: number?) or 0) + 1)
	end
end

local function studioTargets(): { Player }
	local target = ServerScriptService:GetAttribute(TARGET_SWITCH)
	if type(target) == "number" and target ~= 0 then
		local player = Players:GetPlayerByUserId(target)
		return if player then { player } else {}
	end
	return Players:GetPlayers()
end

local function ensure(name: string, default: any)
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, default)
	end
end

-- "<egg>" or "<egg> <times>", e.g. "1 2" for two purchases in the same frame (double tap).
local function parsePurchase(value: any): (number?, number?)
	if type(value) ~= "string" then
		return nil, nil
	end
	local egg, times = string.match(value, "^%s*(%d+)%s*(%d*)%s*$")
	if egg == nil then
		return nil, nil
	end
	local n = if times == "" then 1 else tonumber(times)
	if n == nil or n < 1 or n > MAX_REPEAT then
		return nil, nil
	end
	return tonumber(egg), n
end

local function setUpStudio(stations: any)
	core.subscribe(onStudioEvent :: any)
	ensure(FORCE_SWITCH, "")
	ensure(PURCHASE_SWITCH, "")
	ensure(GEOMETRY_SWITCH, false)

	ServerScriptService:GetAttributeChangedSignal(FORCE_SWITCH):Connect(function()
		local value = ServerScriptService:GetAttribute(FORCE_SWITCH)
		if value ~= "" and forcedRarity() == nil then
			warn(`[EggService] {FORCE_SWITCH}: {tostring(value)} is not a rarity of Egg 1; hatches roll normally`)
		else
			print(`[EggService] {FORCE_SWITCH} -> {if value == "" then "normal roll" else value}`)
		end
	end)

	-- The core path of the remote without the Net guard and without the station distance.
	ServerScriptService:GetAttributeChangedSignal(PURCHASE_SWITCH):Connect(function()
		local value = ServerScriptService:GetAttribute(PURCHASE_SWITCH)
		if value == "" or value == nil then
			return
		end
		ServerScriptService:SetAttribute(PURCHASE_SWITCH, "")
		local egg, times = parsePurchase(value)
		if egg == nil then
			warn(`[EggService] {PURCHASE_SWITCH}: expected "<egg> [times 1..{MAX_REPEAT}]", got {tostring(value)}`)
			return
		end
		for _, player in studioTargets() do
			for _ = 1, times :: number do
				core.purchase(player.UserId, egg, STUDIO_REASON)
			end
		end
	end)

	ServerScriptService:GetAttributeChangedSignal(GEOMETRY_SWITCH):Connect(function()
		local enabled = ServerScriptService:GetAttribute(GEOMETRY_SWITCH) == true
		local origin: CFrame? = nil
		local target = studioTargets()[1]
		local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			origin = root.CFrame
		end
		print(`[EggService] {GEOMETRY_SWITCH} -> {stations.setTestGeometry(enabled, origin)}`)
	end)
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function setUp()
	if started then
		return
	end
	started = true

	core.subscribe(onEvent :: any)
	Players.PlayerRemoving:Connect(function(player: Player)
		core.forget(player.UserId)
	end)

	local prompt = PromptSpec.resolve("EggStation", UiConfig)
	local stations = EggStations.start({
		map = MapConfig,
		studioTest = EggsConfig.StudioTest,
		worldIndex = PlaceInfo.WorldIndex :: number,
		zoneCount = ZonesConfig.ZoneCount,
		isZone = Formulas.Zones.isZone,
		worldOf = Formulas.Zones.worldOf,
		eggForZone = PetCatalogue.eggForZone,
		isAvailable = PetCatalogue.isAvailable,
		reach = prompt.MaxActivationDistance + EggsConfig.StationReachTolerance,
		log = function(message: string)
			log("info", message)
		end,
	})

	-- The egg comes from the station the server finds at the character, never from the client.
	NetService.handle(REMOTE, function(player: Player)
		local position = rootPosition(player)
		local egg = if position then stations.eggNear(position) else nil
		if egg == nil then
			core.refuse(player.UserId, REMOTE_REASON, EggCore.Refusal.NoStation)
			return
		end
		core.purchase(player.UserId, egg, REMOTE_REASON)
	end)

	if studioTools then
		setUpStudio(stations)
	end
	print(
		`[EggService] started eggs={Formulas.Pets.eggCount} egg1Price={Formulas.Pets.eggPrice(1)} stations={stations.count()} studioSwitches={studioTools}`
	)
end

function EggService.Start()
	setUp()
end

-- Every Hatched and Refused event, for analytics (#43). Returns an unsubscribe function.
function EggService.Subscribe(listener: (event: Event) -> ()): () -> ()
	return core.subscribe(listener :: any)
end

return EggService

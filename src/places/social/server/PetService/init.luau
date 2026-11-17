--!strict
-- PetService (Lobby and Simulator, concept 7.9, ADR 0003, ADR 0013): the pet inventory, equip
-- slots and the pet multiplier. The only writer of `sim.pets`. The rules are in the pure PetCore;
-- this file wires them to DataService, Net and the player attributes.
--
-- It lives in `src/places/social/server` because ADR 0003 runs PetService in the Lobby and the
-- Simulator. In the Vertical Slice only the Simulator has a pets window and followers; the
-- Lobby part (window, following) is #103. In the Lobby this service already publishes the same
-- attributes and accepts PetEquip, so #103 adds only client code there.
--
-- A client sends only `PetEquip(uid, equipped)`. Ownership, slots and the multiplier are decided
-- here. Pets reach the inventory through AddPet (EggService). Like coins and upgrades, a change
-- is not an immediate save (ADR 0003): it lands with the next autosave or the leave save.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local PetsConfig = require(Config:WaitForChild("Pets")) :: any
local DataConfig = require(Config:WaitForChild("Data")) :: any
local NetConfig = require(Config:WaitForChild("Net")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local PetCatalogue = require(Shared:WaitForChild("PetCatalogue")) :: any
local PetCodec = require(Shared:WaitForChild("PetCodec"))

local PetAttributes = require(script:WaitForChild("PetAttributes"))
local PetCore = require(script:WaitForChild("PetCore"))

local Services = script.Parent.Parent:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local NetService = require(Services:WaitForChild("NetService"))

local REMOTE = "PetEquip"
local REMOTE_REASON = "Remote"
local STUDIO_REASON = "StudioSwitch"

-- Studio-only switches on ServerScriptService (ADR 0013). EggService reads the same target.
local TARGET_SWITCH = "PetTargetUserId"
local GRANT_SWITCH = "PetGrant"
local CLEAR_SWITCH = "PetClear"
local PREVIEW_SWITCH = "PetFollowForeignPreview"
local LAST_CHANGE = "PetLastChange"
-- A PetGrant count above this is refused, so a typo never loops for long.
local MAX_GRANT = 200

-- Mirrors PetCore.Event (types of WaitForChild requires are not visible here).
type Event = {
	kind: "Added" | "Equipped" | "Unequipped" | "Cleared" | "Refused",
	userId: number,
	uid: string?,
	pet: string?,
	count: number?,
	reason: string,
	refusal: string?,
}

local PetService = {}

local isStudio = RunService:IsStudio()
local studioTools = isStudio and game.PlaceId == 0
local started = false
local changed = Instance.new("BindableEvent")
local random = Random.new()

-- Fires (player) after the player's pets or their equip state changed, and when the profile
-- loads. PetMultiplier is already written when it fires.
PetService.Changed = changed.Event

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[PetService] {message}`)
	elseif isStudio then
		print(`[PetService] {message}`)
	end
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local core = PetCore.new({
	catalogue = PetCatalogue,
	formulas = Formulas.Pets,
	defaultInventorySize = DataConfig.InventorySize,
	maxUidLength = NetConfig.Pets.MaxUidLength,
	getProfile = function(userId: number): any
		local player = playerOf(userId)
		if player == nil then
			return nil
		end
		return DataService.GetProfile(player)
	end,
	-- "<userId>_<unix time hex>_<16-bit random hex>": unique across players by the prefix, and
	-- PetCore retries on the (second-and-random) clash with the player's own pets.
	newUid = function(userId: number): string
		return string.format("%d_%x_%04x", userId, os.time(), random:NextInteger(0, 0xFFFF))
	end,
	hasSlotsPass = function(_userId: number): boolean
		return false -- the +3 slots game pass comes with monetisation (9.2)
	end,
	log = log,
})

local attributes = PetAttributes.new({
	multiplierName = PetsConfig.MultiplierAttribute,
	names = PetsConfig.Attributes,
	entries = core.entries,
	multiplier = core.multiplier,
	slots = core.slots,
	capacity = core.capacity,
	count = core.count,
	encodeInventory = PetCodec.encodeInventory,
	encodeEquipped = PetCodec.encodeEquipped,
	diagnostics = studioTools,
})

local function publish(player: Player)
	if attributes.mirror(player, player.UserId) then
		changed:Fire(player)
	end
end

local function describe(event: Event): string
	local pet = if event.pet then ` {event.pet}` else ""
	local uid = if event.uid then ` uid={event.uid}` else ""
	if event.kind == "Refused" then
		return `{event.reason} refused: {event.refusal}{pet}{uid}`
	elseif event.kind == "Cleared" then
		return `{event.reason} cleared {event.count} pets`
	end
	return `{event.reason} {event.kind}{pet}{uid} multiplier={core.multiplier(event.userId)}`
end

local function onStudioEvent(event: Event)
	local player = playerOf(event.userId)
	local text = describe(event)
	print(`[PetService] {if player then player.Name else "?"} ({event.userId}) {text}`)
	if player then
		player:SetAttribute(LAST_CHANGE, text)
	end
end

-- Targets of a Studio switch: PetTargetUserId, or every player when it is 0.
local function studioTargets(): { Player }
	local target = ServerScriptService:GetAttribute(TARGET_SWITCH)
	if type(target) == "number" and target ~= 0 then
		local player = Players:GetPlayerByUserId(target)
		if player == nil then
			warn(`[PetService] {TARGET_SWITCH}: no player with UserId {target}`)
			return {}
		end
		return { player }
	end
	return Players:GetPlayers()
end

local function ensure(name: string, default: any)
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, default)
	end
end

-- "<kind>" or "<kind> <count>", e.g. "RedFox 3". Returns nil for anything else.
local function parseGrant(value: any): (string?, number?)
	if type(value) ~= "string" then
		return nil, nil
	end
	local kind, amount = string.match(value, "^%s*(%w+)%s*(%d*)%s*$")
	if kind == nil then
		return nil, nil
	end
	local n = if amount == "" then 1 else tonumber(amount)
	if n == nil or n < 1 or n > MAX_GRANT then
		return nil, nil
	end
	return kind, n
end

local function setUpStudio()
	core.subscribe(onStudioEvent :: any)
	ensure(TARGET_SWITCH, 0)
	ensure(GRANT_SWITCH, "")
	ensure(CLEAR_SWITCH, false)
	ensure(PREVIEW_SWITCH, false)

	-- Through the same add() path as a hatch: kind and inventory limit are checked.
	ServerScriptService:GetAttributeChangedSignal(GRANT_SWITCH):Connect(function()
		local value = ServerScriptService:GetAttribute(GRANT_SWITCH)
		if value == "" or value == nil then
			return
		end
		ServerScriptService:SetAttribute(GRANT_SWITCH, "")
		local kind, amount = parseGrant(value)
		if kind == nil then
			warn(`[PetService] {GRANT_SWITCH}: expected "<kind> [count]" (count 1..{MAX_GRANT}), got {tostring(value)}`)
			return
		end
		for _, player in studioTargets() do
			for _ = 1, amount :: number do
				if not core.add(player.UserId, kind, STUDIO_REASON) then
					break
				end
			end
		end
	end)

	ServerScriptService:GetAttributeChangedSignal(CLEAR_SWITCH):Connect(function()
		if ServerScriptService:GetAttribute(CLEAR_SWITCH) ~= true then
			return
		end
		ServerScriptService:SetAttribute(CLEAR_SWITCH, false)
		for _, player in studioTargets() do
			core.clear(player.UserId, STUDIO_REASON)
		end
	end)

	-- The client draws the local player's own pets a second time through the simplified path of
	-- foreign pets (ADR 0013), so R2 can be checked with one player.
	local function applyPreview(player: Player)
		player:SetAttribute(PREVIEW_SWITCH, ServerScriptService:GetAttribute(PREVIEW_SWITCH) == true)
	end
	ServerScriptService:GetAttributeChangedSignal(PREVIEW_SWITCH):Connect(function()
		for _, player in studioTargets() do
			applyPreview(player)
		end
	end)
	Players.PlayerAdded:Connect(applyPreview)
end

local function setUp()
	if started then
		return
	end
	started = true

	-- Every server: attributes after every change. A refusal changes nothing.
	core.subscribe(function(event: any)
		if event.kind == "Refused" then
			return
		end
		local player = playerOf(event.userId)
		if player then
			publish(player)
		end
	end)
	DataService.LoadStatusChanged:Connect(function(player: Player, status: string)
		if status == "Loaded" then
			publish(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if DataService.GetProfile(player) ~= nil then
			publish(player)
		end
	end

	NetService.handle(REMOTE, function(player: Player, uid: string, equipped: boolean)
		core.setEquipped(player.UserId, uid, equipped, REMOTE_REASON)
	end)

	if studioTools then
		setUpStudio()
	end
	print(
		`[PetService] started pets={#PetCatalogue.ids} inventory={DataConfig.InventorySize} multiplierAttribute={PetsConfig.MultiplierAttribute} studioSwitches={studioTools}`
	)
end

function PetService.Start()
	setUp()
end

-- Adds one pet of `kind` (a Config.Pets.Catalogue id). Returns true and the new uid, or false and
-- a refusal (NotLoaded, BadProfile, BadKind, InventoryFull, UidClash). Never yields.
function PetService.AddPet(player: Player, kind: string, reason: string): (boolean, string)
	setUp()
	return core.add(player.UserId, kind, reason)
end

-- True when one more pet fits, else false and NotLoaded, BadProfile or InventoryFull.
function PetService.HasRoom(player: Player): (boolean, string?)
	return core.hasRoom(player.UserId)
end

-- 1 + the bonuses of the equipped pets (concept 7.9); 1 while the profile is not loaded. The
-- same value as the PetMultiplier attribute.
function PetService.GetMultiplier(player: Player): number
	return core.multiplier(player.UserId)
end

-- Every Added, Equipped, Unequipped, Cleared and Refused event, for analytics (#43). Returns an
-- unsubscribe function.
function PetService.Subscribe(listener: (event: Event) -> ()): () -> ()
	return core.subscribe(listener :: any)
end

return PetService

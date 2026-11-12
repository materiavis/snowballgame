--!strict
-- UpgradeService (Simulator only, concept 7.8, ADR 0010): five coin upgrades with
-- Config.Upgrades.MaxLevel levels each. The only writer of `sim.upgrades`. The rules are in the
-- pure UpgradeCore; this file wires them to DataService, CurrencyService, Net and the map.
--
-- A client sends only an upgrade id (remote `UpgradeBuy`). The level comes from the profile, the
-- price from Formulas.Upgrades, the coins check from CurrencyService. A purchase is not an
-- immediate save (ADR 0003): it lands with the next autosave or the leave save, like coins.
--
-- Effects are read by their owners: BallService (growth, stability through GrowthModifiers),
-- MovementService (walk speed, on LevelChanged), and later selling (#38, sellValue) and finds
-- (#40, magnet) through GetLevel / GetEffect.
--
-- Every server mirrors the levels to `Upgrade<Id>Level` player attributes (the HUD contract).
-- In Studio at PlaceId 0 the effects, the last purchase and switches on ServerScriptService are
-- added (ADR 0010). Live servers skip those.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local UpgradesConfig = require(Config:WaitForChild("Upgrades")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local UiConfig = require(Config:WaitForChild("Ui")) :: any
local ZonesConfig = require(Config:WaitForChild("Zones")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))
local UpgradeAttributes = require(Shared:WaitForChild("UpgradeAttributes"))

local LevelAttributes = require(script:WaitForChild("LevelAttributes"))
local UpgradeCore = require(script:WaitForChild("UpgradeCore"))
local UpgradeStands = require(script:WaitForChild("UpgradeStands"))

local Services = script.Parent.Parent:WaitForChild("Services")
local CurrencyService = require(Services:WaitForChild("CurrencyService"))
local DataService = require(Services:WaitForChild("DataService"))
local NetService = require(Services:WaitForChild("NetService"))

local REMOTE = "UpgradeBuy"
local REMOTE_REASON = "Remote"

-- Studio-only switches on ServerScriptService (ADR 0010).
local TARGET_SWITCH = "UpgradeTargetUserId"
local BUY_SWITCH = "UpgradePurchase"
local SET_LEVEL_SWITCH = "UpgradeSetLevel"
local TEST_STANDS_SWITCH = "UpgradeStandTestGeometry"
local STUDIO_REASON = "StudioSwitch"

-- Mirrors UpgradeCore.Event (types of WaitForChild requires are not visible here).
type Event = {
	kind: "Purchase" | "Set" | "Refused",
	userId: number,
	upgrade: any,
	from: number?,
	to: number?,
	price: number?,
	reason: string,
	refusal: string?,
}

local UpgradeService = {}

local isStudio = RunService:IsStudio()
local studioTools = isStudio and game.PlaceId == 0
local started = false
local levelChanged = Instance.new("BindableEvent")

-- Fires (player, upgradeId, level) after a purchase or a Studio switch changed a level, and for
-- every upgrade when the profile loads. MovementService applies walk speed from it.
UpgradeService.LevelChanged = levelChanged.Event

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[UpgradeService] {message}`)
	elseif isStudio then
		print(`[UpgradeService] {message}`)
	end
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local core = UpgradeCore.new({
	config = UpgradesConfig,
	formulas = Formulas.Upgrades,
	getProfile = function(userId: number): any
		local player = playerOf(userId)
		if player == nil then
			return nil
		end
		return DataService.GetProfile(player)
	end,
	spendCoins = function(userId: number, amount: number, reason: string): (boolean, any)
		local player = playerOf(userId)
		if player == nil then
			return false, UpgradeCore.Refusal.NotLoaded
		end
		return CurrencyService.SpendCoins(player, amount, reason)
	end,
	log = log,
})

local attributes = LevelAttributes.new({
	ids = UpgradesConfig.Order,
	level = function(userId: number, id: string): number?
		return (core.level(userId, id))
	end,
	effect = Formulas.Upgrades.effect,
	levelName = UpgradeAttributes.level,
	effectName = UpgradeAttributes.effect,
	diagnostics = studioTools,
})

local function onLoaded(player: Player)
	attributes.mirror(player, player.UserId)
	for _, id in UpgradesConfig.Order do
		levelChanged:Fire(player, id, core.levelOrZero(player.UserId, id))
	end
end

-- Every server: attributes and LevelChanged after every change. A refusal changes nothing.
local function onEvent(event: Event)
	if event.kind == "Refused" then
		return
	end
	local player = playerOf(event.userId)
	if player == nil then
		return
	end
	attributes.mirror(player, event.userId)
	levelChanged:Fire(player, event.upgrade, event.to)
end

local function effectText(id: string, level: number?): string
	if level == nil then
		return "?"
	end
	return string.format("%.4g", Formulas.Upgrades.effect(id, level))
end

local function describe(event: Event): string
	local id = tostring(event.upgrade)
	if event.kind == "Refused" then
		local level = if event.from ~= nil then ` level={event.from}` else ""
		local price = if event.price ~= nil then ` price={event.price}` else ""
		return `{id} {event.reason} refused: {event.refusal}{level}{price}`
	end
	local effects = `effect {effectText(id, event.from)} -> {effectText(id, event.to)}`
	if event.kind == "Purchase" then
		return `{id} {event.from} -> {event.to} price={event.price} {event.reason} {effects}`
	end
	return `{id} set {tostring(event.from)} -> {event.to} {event.reason} {effects}`
end

local function onStudioEvent(event: Event)
	local player = playerOf(event.userId)
	local text = describe(event)
	print(`[UpgradeService] {if player then player.Name else "?"} ({event.userId}) {text}`)
	if player == nil then
		return
	end
	player:SetAttribute(UpgradeAttributes.LAST_PURCHASE, text)
	if event.kind == "Refused" then
		local refusals = (player:GetAttribute(UpgradeAttributes.REFUSALS) :: number?) or 0
		player:SetAttribute(UpgradeAttributes.REFUSALS, refusals + 1)
	end
end

-- Targets of a Studio switch: UpgradeTargetUserId, or every player when it is 0.
local function studioTargets(): { Player }
	local target = ServerScriptService:GetAttribute(TARGET_SWITCH)
	if type(target) == "number" and target ~= 0 then
		local player = Players:GetPlayerByUserId(target)
		if player == nil then
			warn(`[UpgradeService] {TARGET_SWITCH}: no player with UserId {target}`)
			return {}
		end
		return { player }
	end
	return Players:GetPlayers()
end

-- A string switch runs once per value and resets itself to "".
local function bindTextSwitch(name: string, action: (value: any) -> ())
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, "")
	end
	ServerScriptService:GetAttributeChangedSignal(name):Connect(function()
		local value = ServerScriptService:GetAttribute(name)
		if value == "" or value == nil then
			return
		end
		ServerScriptService:SetAttribute(name, "")
		action(value)
	end)
end

local function setUpStudio(stands: any)
	core.subscribe(onStudioEvent :: any)
	if ServerScriptService:GetAttribute(TARGET_SWITCH) == nil then
		ServerScriptService:SetAttribute(TARGET_SWITCH, 0)
	end

	-- The same path as the remote, without the Net guard: id checks, level, price and coins.
	bindTextSwitch(BUY_SWITCH, function(value)
		for _, player in studioTargets() do
			core.purchase(player.UserId, value, STUDIO_REASON)
		end
	end)

	-- "<id> <level>", e.g. "walkSpeed 100". Id and level go through setLevel's checks.
	bindTextSwitch(SET_LEVEL_SWITCH, function(value)
		local id, level = UpgradeCore.parseSetLevel(value)
		if id == nil then
			warn(`[UpgradeService] {SET_LEVEL_SWITCH}: expected "<id> <level>", got {tostring(value)}`)
			return
		end
		for _, player in studioTargets() do
			core.setLevel(player.UserId, id, level, STUDIO_REASON)
		end
	end)

	if ServerScriptService:GetAttribute(TEST_STANDS_SWITCH) == nil then
		ServerScriptService:SetAttribute(TEST_STANDS_SWITCH, false)
	end
	ServerScriptService:GetAttributeChangedSignal(TEST_STANDS_SWITCH):Connect(function()
		local enabled = ServerScriptService:GetAttribute(TEST_STANDS_SWITCH) == true
		local origin: CFrame? = nil
		local target = studioTargets()[1]
		local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			origin = root.CFrame
		end
		print(`[UpgradeService] {TEST_STANDS_SWITCH} -> {stands.setTestGeometry(enabled, origin)}`)
	end)
end

local function setUp()
	if started then
		return
	end
	started = true

	core.subscribe(onEvent :: any)
	DataService.LoadStatusChanged:Connect(function(player: Player, status: string)
		if status == "Loaded" then
			onLoaded(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if DataService.GetProfile(player) ~= nil then
			onLoaded(player)
		end
	end

	NetService.handle(REMOTE, function(player: Player, id: string)
		core.purchase(player.UserId, id, REMOTE_REASON)
	end)

	local stands = UpgradeStands.start({
		map = MapConfig,
		text = UiConfig.Text,
		worldIndex = PlaceInfo.WorldIndex :: number,
		zoneCount = ZonesConfig.ZoneCount,
		isZone = Formulas.Zones.isZone,
		worldOf = Formulas.Zones.worldOf,
		log = function(message: string)
			log("info", message)
		end,
	})

	if studioTools then
		setUpStudio(stands)
	end
	print(
		`[UpgradeService] started upgrades={table.concat(UpgradesConfig.Order, ",")} maxLevel={UpgradesConfig.MaxLevel} stands={stands.count()} studioSwitches={studioTools}`
	)
end

function UpgradeService.Start()
	setUp()
end

-- The player's level of `id` (a Config.Upgrades id), 0 while the profile is not loaded. Errors
-- on an unknown id. For effect owners: BallService, MovementService, selling (#38), finds (#40).
function UpgradeService.GetLevel(player: Player, id: string): number
	return core.levelOrZero(player.UserId, id)
end

-- The effect at the player's level (Formulas.Upgrades.effect): seconds to MAX (growth), studs/s
-- (walkSpeed), studs (magnet), sell multiplier (sellValue), size share lost per hit (stability).
function UpgradeService.GetEffect(player: Player, id: string): number
	return Formulas.Upgrades.effect(id, core.levelOrZero(player.UserId, id))
end

-- Price of the next level, or nil at the maximum or while not loaded.
function UpgradeService.GetNextPrice(player: Player, id: string): number?
	return core.nextPrice(player.UserId, id)
end

-- Every Purchase, Set and Refused event, for AnalyticsService (#43). Returns an unsubscribe.
function UpgradeService.Subscribe(listener: (event: Event) -> ()): () -> ()
	return core.subscribe(listener :: any)
end

return UpgradeService

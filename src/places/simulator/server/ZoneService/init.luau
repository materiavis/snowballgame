--!strict
-- ZoneService (Simulator only, concept 7.6 and 6.5, ADR 0009, ADR 0014): zones 1-5 of the
-- Vertical Slice. The only writer of `sim.unlockedZones`, `sim.lastZone` and `sim.highestZone`.
-- The rules are in the pure ZoneCore, the map reading in ZoneMap / ZoneAreas; this file wires
-- them to DataService, CurrencyService, BallService, Net and PopupService.
--
-- * Barriers: a client sends only the zone to open (remote ZoneUnlock). Cap, map, adjacency,
--   unlocked set, price and coins are checked here; a paid barrier is saved at once (6.5).
-- * Current zone: the server checks which zone area each character stands in. Entering an
--   unlocked zone moves the ball into it with its size kept (BallService.EnterZone); entering a
--   zone that is not unlocked sends the player back to the start of their zone. The barrier
--   itself blocks on the client (collision group, ZoneController), this is the server's check.
-- * Spawn, respawn and rejoin go to the start of the current / last visited zone. The zone
--   teleport (remote ZoneTeleport) goes to an unlocked zone's start, then waits
--   Config.Zones.ZoneTeleportWait.
--
-- Every server mirrors the unlocked zones to the player attribute ZonesUnlocked. In Studio at
-- PlaceId 0 diagnostics and switches are added (ZoneStudio). Live servers skip those.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BallConfig = require(Config:WaitForChild("Ball")) :: any
local DisplayConfig = require(Config:WaitForChild("Display")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local ZonesConfig = require(Config:WaitForChild("Zones")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))
local PopupAmount = require(Shared:WaitForChild("PopupAmount"))
local ZoneAttributes = require(Shared:WaitForChild("ZoneAttributes"))

local ZoneCore = require(script:WaitForChild("ZoneCore"))
local ZoneMap = require(script:WaitForChild("ZoneMap"))
local ZoneStudio = require(script:WaitForChild("ZoneStudio"))
local ZoneTestGeometry = require(script:WaitForChild("ZoneTestGeometry"))

local PlaceServices = script.Parent
local BallService = require(PlaceServices:WaitForChild("BallService"))
local CollisionSetup = require(PlaceServices:WaitForChild("BallService"):WaitForChild("CollisionSetup"))
local Services = PlaceServices.Parent:WaitForChild("Services")
local CurrencyService = require(Services:WaitForChild("CurrencyService"))
local DataService = require(Services:WaitForChild("DataService"))
local NetService = require(Services:WaitForChild("NetService"))
local PopupService = require(Services:WaitForChild("PopupService"))

local UNLOCK_REMOTE = "ZoneUnlock"
local TELEPORT_REMOTE = "ZoneTeleport"
local REMOTE_REASON = "Remote"
local STUDIO_REASON = "StudioSwitch"
local SAVE_REASON = "Barrier"
local INSUFFICIENT = "Insufficient" -- CurrencyService refusal

local R = ZoneCore.Refusal
local areaConfig = MapConfig.ZoneAreas

local ZoneService = {}

local isStudio = RunService:IsStudio()
local studioTools = isStudio and game.PlaceId == 0
local started = false

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[ZoneService] {message}`)
	elseif isStudio then
		print(`[ZoneService] {message}`)
	end
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- Assigned in setUp. ZoneCore reads the map through this view only at call time.
local zoneMap: any = nil
local mapView = {
	hasZone = function(zone: number): boolean
		return zoneMap ~= nil and zoneMap.hasZone(zone)
	end,
	hasBarrier = function(zone: number): boolean
		return zoneMap ~= nil and zoneMap.hasBarrier(zone)
	end,
}

local core = ZoneCore.new({
	config = ZonesConfig,
	formulas = Formulas.Zones,
	worldIndex = PlaceInfo.WorldIndex :: number,
	map = mapView,
	getProfile = function(userId: number): any
		local player = playerOf(userId)
		return if player then DataService.GetProfile(player) else nil
	end,
	spendCoins = function(userId: number, amount: number, reason: string): (boolean, any)
		local player = playerOf(userId)
		if player == nil then
			return false, R.NotLoaded
		end
		return CurrencyService.SpendCoins(player, amount, reason)
	end,
	now = os.clock,
	log = log,
})

local missingUp = PopupAmount.new(DisplayConfig)
local graceUntil: { [Player]: number } = {}
-- Zone the ball still has to follow: set when BallService had no ball yet (first join, the
-- profile loaded before the character), retried by the position check.
local pendingBall: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and (humanoid == nil or humanoid.Health > 0) then
		return root
	end
	return nil
end

local function publishUnlocked(player: Player)
	local list = core.unlocked(player.UserId)
	player:SetAttribute(ZoneAttributes.UNLOCKED, if list then ZoneAttributes.encode(list) else nil)
end

-- The player counts in `zone` from now on; the ball follows with its size kept.
local function enterZone(player: Player, zone: number, reason: string): boolean
	local ok = core.enter(player.UserId, zone, reason)
	if ok then
		pendingBall[player] = if BallService.EnterZone(player, zone) then nil else zone
	end
	return ok
end

-- Character (and then the ball) to the start of `zone`. `stream` waits for the target area to
-- stream in for the player first, so a far teleport does not land on parts the client lacks.
local function moveToStart(player: Player, zone: number, stream: boolean): boolean
	local target: CFrame? = zoneMap.startCFrame(zone)
	if target == nil then
		return false
	end
	if stream then
		local ok, err = pcall(function()
			player:RequestStreamAroundAsync(target.Position, areaConfig.StreamTimeout)
		end)
		if not ok then
			log("warn", `{player.Name} stream around zone {zone} start failed: {err}`)
		end
	end
	local character = player.Character
	if character == nil or rootOf(player) == nil then
		return false
	end
	graceUntil[player] = os.clock() + areaConfig.ReturnGrace
	character:PivotTo(target)
	BallService.PlaceAtCharacter(player)
	return true
end

-- Start of the current zone, or (no current zone yet) of the last visited one (6.5).
local function placeAtStart(player: Player, reason: string)
	local zone = core.current(player.UserId) or core.startZone(player.UserId)
	if zone == nil then
		return -- no zone areas in this map: Roblox's spawn stays
	end
	enterZone(player, zone, reason)
	moveToStart(player, zone, true)
end

local function purchase(player: Player, zone: any, reason: string)
	local ok, result = core.purchase(player.UserId, zone, reason)
	if not ok then
		if result == INSUFFICIENT then
			local coins = CurrencyService.GetCoins(player)
			if coins ~= nil then
				local missing = math.max(0, Formulas.Zones.barrierPrice(zone - 1) - coins)
				PopupService.show(player, "BarrierNeedMore", { missingUp(missing) })
			end
		end
		return
	end
	PopupService.show(player, "ZoneUnlocked", { zone })
	-- Concept 6.5: paid barriers are saved at once. On failure the unlock and the spend stay on
	-- the server together and the next autosave or the leave save stores both (ADR 0014).
	local saved, err = DataService.SaveNow(player, SAVE_REASON)
	local text = if saved then `zone {zone} saved` else `zone {zone} save failed: {err}`
	if not saved then
		log("warn", `{player.Name} {text}; kept on the server for the next save`)
	end
	if studioTools then
		player:SetAttribute(ZoneAttributes.LAST_SAVE, text)
		print(`[ZoneService] {player.Name} ({player.UserId}) {text}`)
	end
end

local function teleport(player: Player, zone: any, reason: string)
	if rootOf(player) == nil then
		core.refuse(player.UserId, "Teleport", zone, reason, R.NoCharacter)
		PopupService.show(player, "ZoneTeleportFailed")
		return
	end
	local ok, refusal, remaining = core.teleport(player.UserId, zone, reason)
	if not ok then
		if refusal == R.Wait and remaining then
			PopupService.show(player, "ZoneTeleportWait", { math.max(1, math.ceil(remaining)) })
		else
			PopupService.show(player, "ZoneTeleportFailed")
		end
		return
	end
	enterZone(player, zone, reason)
	if not moveToStart(player, zone, true) then
		PopupService.show(player, "ZoneTeleportFailed")
	end
end

-- One server check of where the character stands (ADR 0014 "Current zone").
local function check(player: Player)
	if DataService.GetProfile(player) == nil or (graceUntil[player] or 0) > os.clock() then
		return
	end
	local pending = pendingBall[player]
	if pending ~= nil and BallService.EnterZone(player, pending) then
		pendingBall[player] = nil
	end
	local root = rootOf(player)
	if root == nil then
		return
	end
	local userId = player.UserId
	local current = core.current(userId)
	local zone = zoneMap.zoneAt(root.Position, current)
	if zone == nil or zone == current then
		return
	end
	if core.isUnlocked(userId, zone) then
		enterZone(player, zone, "Walk")
		return
	end
	-- Past a closed barrier (an exploit, or a reset while inside): back to the own zone.
	core.refuse(userId, "Enter", zone, "Walk", R.Locked)
	local back = current or core.startZone(userId)
	if back == nil or not moveToStart(player, back, false) then
		graceUntil[player] = os.clock() + areaConfig.ReturnGrace
		log("warn", `{player.Name} is in locked zone {zone} and has no zone start to return to`)
	end
end

local function onLoaded(player: Player)
	publishUnlocked(player)
	-- A (re)load starts over in the last visited zone, not in a zone from an older session.
	core.forget(player.UserId)
	if rootOf(player) then
		placeAtStart(player, "Join")
	else
		local zone = core.startZone(player.UserId)
		if zone then
			enterZone(player, zone, "Join")
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		if player.Character == character and DataService.GetProfile(player) ~= nil then
			placeAtStart(player, "Spawn")
		end
	end)
	if DataService.GetProfile(player) ~= nil then
		task.spawn(onLoaded, player)
	end
end

local function describe(event: any): string
	local price = if event.price ~= nil then ` price={event.price}` else ""
	if event.kind == "Refused" then
		return `{event.action} zone {tostring(event.zone)} {event.reason} refused: {event.refusal}{price}`
	end
	return `{event.action} zone {tostring(event.zone)} {event.reason}{price}`
end

local function setUpStudio()
	core.subscribe(function(event: any)
		local player = playerOf(event.userId)
		local text = describe(event)
		print(`[ZoneService] {if player then player.Name else "?"} ({event.userId}) {text}`)
		if player == nil then
			return
		end
		if event.kind == "Refused" then
			player:SetAttribute(ZoneAttributes.LAST_REFUSAL, text)
			local count = (player:GetAttribute(ZoneAttributes.REFUSALS) :: number?) or 0
			player:SetAttribute(ZoneAttributes.REFUSALS, count + 1)
		else
			player:SetAttribute(ZoneAttributes.LAST_EVENT, text)
		end
		if event.kind == "Enter" or event.kind == "Reset" then
			player:SetAttribute(ZoneAttributes.CURRENT, core.current(event.userId))
		end
	end)

	local function publishMap()
		local cap = tostring(ZonesConfig.HighestOpenZone)
		ServerScriptService:SetAttribute(ZoneStudio.MAP_STATE, `{zoneMap.describe()} cap={cap}`)
	end
	zoneMap.onChanged(publishMap)
	publishMap()

	ZoneStudio.bind(ServerScriptService, {
		purchase = function(player: Player, zone: any)
			purchase(player, zone, STUDIO_REASON)
		end,
		teleport = function(player: Player, zone: any)
			teleport(player, zone, STUDIO_REASON)
		end,
		reset = function(player: Player)
			if core.resetUnlocks(player.UserId, STUDIO_REASON) then
				-- The position check then returns a player standing in a zone above 1.
				core.forget(player.UserId)
				enterZone(player, 1, STUDIO_REASON)
			end
		end,
		setTestGeometry = function(enabled: boolean): string
			local folder = Workspace:FindFirstChild(MapConfig.FolderName)
			if folder == nil then
				return `no Workspace.{MapConfig.FolderName}`
			end
			local options = { map = MapConfig, snowTag = BallConfig.Surfaces.Snow }
			if not enabled then
				ZoneTestGeometry.remove(folder, options)
				zoneMap.refreshNow()
				return "test zones removed"
			end
			local text = ZoneTestGeometry.create(folder, options)
			zoneMap.refreshNow()
			for _, player in ZoneStudio.targets(ServerScriptService) do
				if DataService.GetProfile(player) ~= nil then
					core.forget(player.UserId)
					task.spawn(placeAtStart, player, "TestGeometry")
				end
			end
			return text
		end,
	})
end

local function setUp()
	if started then
		return
	end
	started = true

	-- The open-barrier group next to the ball groups (both registered here, so the order in which
	-- BallService and this service start does not matter; registering is idempotent).
	local groups = table.clone(BallConfig.CollisionGroups)
	groups.OpenBarrier = MapConfig.Barrier.OpenCollisionGroup
	local physics = CollisionSetup.fromPhysicsService(PhysicsService)
	CollisionSetup.apply(physics, groups, MapConfig.Barrier.OpenCollisionRules)
	local rulesOk, rulesText = CollisionSetup.check(physics, MapConfig.Barrier.OpenCollisionRules)
	if not rulesOk then
		log("warn", `open barrier collision rules do not hold: {rulesText}`)
	end

	if not core.capValid() then
		log(
			"warn",
			`Config.Zones.HighestOpenZone {tostring(ZonesConfig.HighestOpenZone)} is invalid: every barrier stays closed`
		)
	end

	zoneMap = ZoneMap.start({
		map = MapConfig,
		worldIndex = PlaceInfo.WorldIndex :: number,
		zoneCount = ZonesConfig.ZoneCount,
		isZone = Formulas.Zones.isZone,
		worldOf = Formulas.Zones.worldOf,
		isWorldGate = Formulas.Zones.isWorldGate,
		barrierState = core.barrierState,
		diagnostics = studioTools,
		log = function(message: string)
			log("info", message)
		end,
	})
	zoneMap.refreshNow()

	core.subscribe(function(event: any)
		if event.kind == "Unlock" or event.kind == "Reset" then
			local player = playerOf(event.userId)
			if player then
				publishUnlocked(player)
			end
		end
	end)
	DataService.LoadStatusChanged:Connect(function(player: Player, status: string)
		if status == "Loaded" then
			onLoaded(player)
		else
			player:SetAttribute(ZoneAttributes.UNLOCKED, nil)
		end
	end)

	NetService.handle(UNLOCK_REMOTE, function(player: Player, zone: number)
		purchase(player, zone, REMOTE_REASON)
	end)
	NetService.handle(TELEPORT_REMOTE, function(player: Player, zone: number)
		teleport(player, zone, REMOTE_REASON)
	end)

	if studioTools then
		setUpStudio()
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		core.forget(player.UserId)
		graceUntil[player] = nil
		pendingBall[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < areaConfig.CheckInterval then
			return
		end
		accumulator = 0
		for _, player in Players:GetPlayers() do
			check(player)
		end
	end)

	print(
		`[ZoneService] started cap={tostring(ZonesConfig.HighestOpenZone)} {zoneMap.describe()} collisions={if rulesOk
			then "ok"
			else "FAILED"} studioSwitches={studioTools}`
	)
end

function ZoneService.Start()
	setUp()
end

-- The zone the server counts the player in, or nil (not loaded, or no zone areas yet).
function ZoneService.GetZone(player: Player): number?
	return core.current(player.UserId)
end

-- Unlocked zones of this world, ascending; nil while the profile is not loaded.
function ZoneService.GetUnlocked(player: Player): { number }?
	return core.unlocked(player.UserId)
end

function ZoneService.IsUnlocked(player: Player, zone: number): boolean
	return core.isUnlocked(player.UserId, zone)
end

-- Shared zone resolver (ADR 0009, ADR 0014) for zone-bound features such as finds (#40).
-- The zone area of an instance below Workspace.Map, or nil.
function ZoneService.ZoneOfInstance(instance: Instance): number?
	setUp()
	return zoneMap.zoneOf(instance)
end

-- The zone area a world position is in, or nil.
function ZoneService.ZoneOfPosition(position: Vector3): number?
	setUp()
	return zoneMap.zoneAt(position, nil)
end

-- A valid zone area with exactly one ZoneStart in this Place.
function ZoneService.HasZone(zone: number): boolean
	setUp()
	return zoneMap.hasZone(zone)
end

-- Unlock, Teleport, Enter, Reset and Refused events, for AnalyticsService (#43).
function ZoneService.Subscribe(listener: (event: any) -> ()): () -> ()
	return core.subscribe(listener)
end

return ZoneService

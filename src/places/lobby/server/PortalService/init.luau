--!strict
-- PortalService: the Lobby portals (concept 7.1, 6.5; ADR 0009, ADR 0015).
-- The server decides from its own view: every PortalCheckInterval it checks whether a
-- character's root is inside a portal's PrimaryPart volume. Inside the open Singleplayer portal
-- a PortalCountdown starts; walking out cancels; at zero TravelService.ToSimulator runs (last
-- world and zone from the profile). The closed Multiplayer portal (Vertical Slice) starts
-- nothing. While DataService.IsPortalLocked (profile not loaded) or another travel runs, no
-- portal starts. There is no remote: the client cannot ask for a portal travel at all.
--
-- Also here: the player counts above the portals (PlayerCounts), the first-join arrow flag
-- (FirstJoinArrow) and the positions the client needs while a portal is streamed out
-- (Workspace attributes, ADR 0009 "StreamingEnabled").
--
-- Every server writes the player attributes the client shows (LobbyAttributes). In Studio at
-- PlaceId 0 the diagnostics and the LobbyStudioSimulatorPlayers switch are added (ADR 0015).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Lobby")) :: any
local TravelConfig = require(Shared:WaitForChild("Config"):WaitForChild("Travel")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes"))

local Services = script.Parent.Parent:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService")) :: any
local PresenceStore = require(Services:WaitForChild("PresenceStore")) :: any
local TravelService = require(Services:WaitForChild("TravelService")) :: any

local LobbyMap = require(script.Parent:WaitForChild("LobbyMap"))
local FirstJoinArrow = require(script:WaitForChild("FirstJoinArrow"))
local PlayerCounts = require(script:WaitForChild("PlayerCounts"))
local PortalCore = require(script:WaitForChild("PortalCore"))

local MapConfig = LobbyMap.Config
local A = LobbyAttributes

local SIMULATOR_PLAYERS_SWITCH = "LobbyStudioSimulatorPlayers"

local PortalService = {}

local studioTools = RunService:IsStudio() and game.PlaceId == 0
local started = false

-- Which travel each open mode starts. Closed modes (Config.Lobby.ClosedPortalModes) have none.
local TRAVELS: { [string]: (player: Player) -> string } = {
	Singleplayer = function(player: Player): string
		return TravelService.ToSimulator(player)
	end,
}

local core = PortalCore.new({
	countdown = LobbyConfig.PortalCountdown,
	closedModes = LobbyConfig.ClosedPortalModes,
	now = function(): number
		return Workspace:GetServerTimeNow()
	end,
})

local portalsBound: () -> { Instance } = function()
	return {}
end

local function log(message: string)
	if RunService:IsStudio() then
		print(`[PortalService] {message}`)
	end
end

local function portalMode(portal: Instance): string?
	local mode = portal:GetAttribute(MapConfig.PortalModeAttribute)
	return if type(mode) == "string" then mode else nil
end

local function portalsOf(mode: string): { Model }
	local list = {}
	for _, portal in portalsBound() do
		if portalMode(portal) == mode then
			table.insert(list, portal :: Model)
		end
	end
	return list
end

-- The first bound portal of each mode publishes its position (the arrow's target, #42 later).
local function publishPositions()
	for _, mode in MapConfig.PortalModes do
		local first = portalsOf(mode)[1]
		local primary = if first then first.PrimaryPart else nil
		Workspace:SetAttribute(A.PORTAL_POSITION_PREFIX .. mode, if primary then primary.Position else nil)
	end
end

local counts = PlayerCounts.new({
	modes = MapConfig.PortalModes,
	refresh = LobbyConfig.PortalPlayerCountRefresh,
	getCount = function(mode: string): number?
		return PresenceStore.GetModeCount(mode)
	end,
	portalsOf = portalsOf,
	countAttribute = MapConfig.PlayerCountAttribute,
	atAttribute = MapConfig.PlayerCountAtAttribute,
	now = os.time,
	wait = function(seconds: number)
		task.wait(seconds)
	end,
	log = log,
})

local function publishArrow(player: Player)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(A.SHOW_SINGLE_ARROW, FirstJoinArrow.shouldShow(DataService.GetProfile(player)))
end

-- result: PortalCore.Result (types of WaitForChild requires are not visible here).
local function apply(player: Player, result: any)
	if result.changed and player.Parent == Players then
		player:SetAttribute(A.PORTAL_STATE, result.state)
		player:SetAttribute(A.PORTAL_MODE, result.mode)
		player:SetAttribute(A.PORTAL_COUNTDOWN_ENDS, result.endsAt)
	end
	if studioTools and player.Parent == Players then
		local left = core.remaining(player.UserId)
		player:SetAttribute(A.PORTAL_COUNTDOWN_LEFT, math.ceil(left * 10) / 10)
		if result.event then
			local text = `{if result.mode ~= "" then result.mode else "-"} {result.event}`
			player:SetAttribute(A.PORTAL_LAST, text)
			log(`{player.Name} ({player.UserId}) {text}`)
		end
	end
end

local function travel(player: Player, mode: string)
	local run = TRAVELS[mode]
	local outcome = "NoTravel"
	if run == nil then
		warn(`[PortalService] {mode} is open but has no travel; nothing happens`)
	else
		local changed = mode == "Singleplayer" and FirstJoinArrow.markSeen(DataService.GetProfile(player))
		publishArrow(player)
		local ok, result = pcall(run, player)
		outcome = if ok then result else "Error"
		if not ok then
			warn(`[PortalService] {mode} travel for {player.Name} errored: {result}`)
		end
		if FirstJoinArrow.afterTravel(DataService.GetProfile(player), changed, outcome) then
			log(`{player.Name} ({player.UserId}) arrow flag restored: travel {outcome}`)
		end
		publishArrow(player)
	end
	if player.Parent ~= Players then
		core.forget(player.UserId)
		return
	end
	if studioTools then
		player:SetAttribute(A.PORTAL_TRAVEL_RESULT, outcome)
	end
	log(`{player.Name} ({player.UserId}) {mode} travel {outcome}`)
	apply(player, core.travelFinished(player.UserId))
end

local function insideMode(player: Player): string?
	local root = LobbyMap.rootOf(player)
	if root == nil then
		return nil
	end
	for _, portal in portalsBound() do
		local primary = (portal :: Model).PrimaryPart
		if primary and LobbyMap.contains(primary, root.Position) then
			return portalMode(portal)
		end
	end
	return nil
end

local function checkPlayer(player: Player)
	local result = core.step(player.UserId, {
		inside = insideMode(player),
		locked = DataService.IsPortalLocked(player),
		travelling = TravelService.IsTraveling(player),
	})
	apply(player, result)
	if result.travel then
		task.spawn(travel, player, result.mode)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(A.PORTAL_STATE, "Idle")
	player:SetAttribute(A.PORTAL_MODE, "")
	player:SetAttribute(A.PORTAL_COUNTDOWN_ENDS, 0)
	publishArrow(player)
end

local function bindSpawns(): () -> { Instance }
	local function publish(list: { Instance })
		local spawn = list[1] :: SpawnLocation?
		Workspace:SetAttribute(
			A.SPAWN_POSITION,
			if spawn then spawn.Position + Vector3.new(0, spawn.Size.Y / 2, 0) else nil
		)
	end
	local spawns: () -> { Instance }
	spawns = LobbyMap.bindTag(MapConfig.Tags.LobbySpawn, LobbyMap.rules.checkSpawn, function()
		task.defer(function()
			publish(spawns())
		end)
	end, function()
		task.defer(function()
			publish(spawns())
		end)
	end)
	publish(spawns())
	return spawns
end

local function setUpStudio()
	if ServerScriptService:GetAttribute(SIMULATOR_PLAYERS_SWITCH) == nil then
		ServerScriptService:SetAttribute(SIMULATOR_PLAYERS_SWITCH, 0)
	end
	-- A fake public Simulator server with n players in the fake PresenceStore, kept fresh like a
	-- real one, so the label changes through the real read path within one refresh.
	task.spawn(function()
		local publishedZero = true
		while true do
			local value = ServerScriptService:GetAttribute(SIMULATOR_PLAYERS_SWITCH)
			local count = if type(value) == "number" and value >= 0 and value % 1 == 0 then value else 0
			if count > 0 or not publishedZero then
				PresenceStore.SetModeCount(TravelConfig.SimulatorMode, LobbyConfig.Test.SimulatorJobId, count)
				publishedZero = count == 0
			end
			task.wait(math.min(1, TravelConfig.PresenceRefresh))
		end
	end)
end

local function setUp()
	if started then
		return
	end
	started = true

	local spawns = bindSpawns()
	portalsBound = LobbyMap.bindTag(MapConfig.Tags.Portal, LobbyMap.rules.checkPortal, function(instance, verdict)
		log(`portal bound {instance:GetFullName()} mode={verdict.mode}`)
		counts.apply(instance :: Model, verdict.mode :: string)
		task.defer(publishPositions)
	end, function(instance)
		log(`portal unbound {instance:GetFullName()}`)
		task.defer(publishPositions)
	end)
	publishPositions()
	LobbyMap.warnCount(MapConfig.Tags.LobbySpawn, #spawns(), "one")
	for _, mode in MapConfig.PortalModes do
		LobbyMap.warnCount(`{MapConfig.Tags.Portal} ({mode})`, #portalsOf(mode), "some")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		core.forget(player.UserId)
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	DataService.LoadStatusChanged:Connect(function(player: Player)
		publishArrow(player)
	end)

	task.spawn(counts.run)
	task.spawn(function()
		while true do
			task.wait(LobbyConfig.PortalCheckInterval)
			for _, player in Players:GetPlayers() do
				checkPlayer(player)
			end
		end
	end)

	if studioTools then
		setUpStudio()
	end
	print(
		`[PortalService] started portals={#portalsBound()} countdown={LobbyConfig.PortalCountdown}s countRefresh={LobbyConfig.PortalPlayerCountRefresh}s studioSwitches={studioTools}`
	)
end

function PortalService.Start()
	setUp()
end

-- Studio reset (LobbyStudioReset, ADR 0015): the first-join arrow shows again.
function PortalService.StudioResetArrow(player: Player): boolean
	assert(studioTools, "PortalService.StudioResetArrow is Studio-only")
	local done = FirstJoinArrow.reset(DataService.GetProfile(player))
	publishArrow(player)
	return done
end

-- Unix time of the last player count refresh (diagnostic).
function PortalService.LastCountRefresh(): number
	return counts.lastRefresh()
end

return PortalService

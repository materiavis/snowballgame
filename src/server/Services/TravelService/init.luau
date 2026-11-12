--!strict
-- TravelService: every change of Place goes through here (concept 5.6, 6.5; ADR 0003, ADR 0010).
-- Save and release (DataService.PrepareTeleport) -> teleport -> on failure take the lock back
-- (ResumeAfterTeleportFailure), show a short message and retry. Picks the server: a friend's
-- Simulator server with a free place, else Roblox matchmaking (free place or a new server);
-- reserved servers for matches and private contexts. Players whose profile does not load are
-- sent back to the Lobby from the other Places.
-- The flow is in the pure TravelCore, Destinations and ServerChoice; this file wires Roblox.
--
-- At game.PlaceId == 0 TeleportService is never fetched: StubTeleporter logs each travel and
-- reports success or a simulated failure, and in Studio the Studio switches (StudioTools) and
-- player attributes TravelState / TravelLast / TravelMessage are set up. Live servers skip both.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local LobbyConfig = require(ConfigFolder:WaitForChild("Lobby")) :: any
local PlacesConfig = require(ConfigFolder:WaitForChild("Places")) :: any
local TravelConfig = require(ConfigFolder:WaitForChild("Travel")) :: any
local ZonesConfig = require(ConfigFolder:WaitForChild("Zones")) :: any
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local NetService = require(script.Parent:WaitForChild("NetService"))
local PresenceStore = require(script.Parent:WaitForChild("PresenceStore"))

local Destinations = require(script:WaitForChild("Destinations"))
local LoadFailReturn = require(script:WaitForChild("LoadFailReturn"))
local RealTeleporter = require(script:WaitForChild("RealTeleporter"))
local ServerChoice = require(script:WaitForChild("ServerChoice"))
local StubTeleporter = require(script:WaitForChild("StubTeleporter"))
local StudioTools = require(script:WaitForChild("StudioTools"))
local TravelCore = require(script:WaitForChild("TravelCore"))

local NOTICE_REMOTE = "TravelNotice"
local LOBBY_REMOTE = "TravelRequestLobby"

-- Mirrors TravelCore.Event (types of WaitForChild requires are not visible here).
type Event = { userId: number, state: string, intent: string, detail: string }

local TravelService = {}

local isStudio = RunService:IsStudio()
local isStub = game.PlaceId == 0
local studioTools = isStudio and isStub
local jobId = if game.JobId ~= "" then game.JobId else "Studio"

local core: any = nil
local started = false
local privateKeyCache: string | boolean | nil = nil

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[TravelService] {message}`)
	elseif isStudio then
		print(`[TravelService] {message}`)
	end
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function nameOf(userId: number): string
	local player = playerOf(userId)
	return if player then player.Name else tostring(userId)
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function notify(userId: number, key: string)
	local player = playerOf(userId)
	if player == nil then
		return
	end
	(NetService.getRemote(NOTICE_REMOTE) :: RemoteEvent):FireClient(player, key)
	if studioTools then
		player:SetAttribute("TravelMessage", key)
	end
end

-- The private context this server belongs to (ADR 0010): a private (VIP) server itself, or a
-- reserved Simulator server that PresenceStore maps to one. Nil on public servers.
local function privateKey(): string?
	if game.PrivateServerId == "" then
		return nil
	end
	if game.PrivateServerOwnerId ~= 0 then
		return game.PrivateServerId
	end
	if PlaceInfo.Role ~= "Simulator" then
		return nil -- an Arena match server; its match record belongs to matchmaking (7.14)
	end
	if privateKeyCache == nil then
		privateKeyCache = PresenceStore.GetPrivateKey(game.PrivateServerId) or false
	end
	return if type(privateKeyCache) == "string" then privateKeyCache else nil
end

local function friendsOf(userId: number): { number }
	if studioTools then
		return StudioTools.friendIds(PresenceStore :: any, LobbyConfig.SimulatorPlayers)
	end
	local player = playerOf(userId)
	if isStub or player == nil then
		return {}
	end
	local ids = {}
	for _, friend in player:GetFriendsOnline(TravelConfig.FriendLookupMax) do
		if type(friend.VisitorId) == "number" then
			table.insert(ids, friend.VisitorId)
		end
	end
	return ids
end

local function makeTeleporter(): any
	if isStub then
		return StubTeleporter.new({
			print = print,
			shouldFail = function()
				return studioTools and StudioTools.takeTeleportFailure()
			end,
			describeTarget = ServerChoice.describe,
		})
	end
	return RealTeleporter.new(game:GetService("TeleportService"), TravelConfig)
end

local function mirror(event: Event)
	local player = playerOf(event.userId)
	if player == nil then
		return
	end
	player:SetAttribute("TravelState", event.state)
	player:SetAttribute("TravelLast", `{event.intent} {event.state}: {event.detail}`)
	print(`[TravelService] {player.Name} ({event.userId}) {event.intent} {event.state}: {event.detail}`)
end

local function publishPresence()
	local userIds = {}
	for _, player in Players:GetPlayers() do
		table.insert(userIds, player.UserId)
	end
	PresenceStore.PublishServer(jobId, PlaceInfo.WorldIndex :: number, userIds)
end

local function setUp()
	if started then
		return
	end
	started = true

	local teleporter = makeTeleporter()
	local destinations = Destinations.new({
		places = PlacesConfig,
		zoneCount = ZonesConfig.ZoneCount,
		zonesPerWorld = ZonesConfig.ZonesPerWorld,
		role = PlaceInfo.Role,
		worldIndex = PlaceInfo.WorldIndex,
	})
	local choice = ServerChoice.new({
		presence = {
			findFriendServer = PresenceStore.FindFriendServer,
			getReserved = PresenceStore.GetReserved,
			setReserved = PresenceStore.SetReserved,
		},
		friendsOf = friendsOf,
		reserve = teleporter.reserve,
		privateKey = privateKey,
		maxSimulatorPlayers = LobbyConfig.SimulatorPlayers,
		ownJobId = jobId,
		log = log,
	})
	local deps = {
		role = PlaceInfo.Role,
		destinations = destinations,
		choice = choice,
		describeTarget = ServerChoice.describe,
		data = {
			prepare = function(userId)
				local player = playerOf(userId)
				if player == nil then
					return false, "NotLoaded"
				end
				return DataService.PrepareTeleport(player)
			end,
			resume = function(userId)
				local player = playerOf(userId)
				if player == nil then
					return false, "NotTeleported"
				end
				return DataService.ResumeAfterTeleportFailure(player)
			end,
			getStatus = function(userId)
				local player = playerOf(userId)
				return if player then DataService.GetLoadStatus(player) else nil
			end,
			getProfile = function(userId)
				local player = playerOf(userId)
				return if player then DataService.GetProfile(player) else nil
			end,
		},
		teleport = teleporter.teleport,
		notify = notify,
		kick = function(userId, message)
			local player = playerOf(userId)
			if player then
				player:Kick(message)
			end
		end,
		isPresent = function(userId)
			return playerOf(userId) ~= nil
		end,
		nameOf = nameOf,
		wait = function(seconds)
			task.wait(seconds)
		end,
		spawn = function(fn)
			task.spawn(fn)
		end,
		log = log,
		allowUnpublished = isStub,
		stayAfterSuccess = isStub,
		config = TravelConfig,
	}
	core = TravelCore.new(deps)
	local loadFail = LoadFailReturn.new(deps, core)

	if studioTools then
		core.subscribe(mirror)
		StudioTools.setUp(function(intent: string)
			local players = Players:GetPlayers()
			if #players == 0 then
				warn("[TravelService] TravelStudioTrigger: no player on this server")
			elseif intent == "LobbyButton" then
				TravelService.RequestLobby(players[1])
			elseif destinations.isIntent(intent) and destinations.isGroup(intent) then
				TravelService.TravelGroup(players, intent)
			else
				TravelService.Travel(players[1], intent)
			end
		end)
	end

	NetService.handle(LOBBY_REMOTE, function(player: Player)
		-- No arguments to check (the guard already enforced count and rate). The destination is
		-- always the Lobby; RequestLobby refuses outside the Simulator and while travelling.
		TravelService.RequestLobby(player)
	end)

	DataService.LoadStatusChanged:Connect(function(player: Player, status: string)
		loadFail.onLoadStatus(player.UserId, status)
	end)
	Players.PlayerRemoving:Connect(function(player)
		loadFail.forget(player.UserId)
	end)

	-- Presence for the friend preference: only public Simulator servers can be joined by JobId.
	if PlaceInfo.Role == "Simulator" and game.PrivateServerId == "" then
		Players.PlayerRemoving:Connect(function(player)
			PresenceStore.RemoveUser(player.UserId)
		end)
		task.spawn(function()
			while true do
				publishPresence()
				task.wait(TravelConfig.PresenceRefresh)
			end
		end)
		game:BindToClose(function()
			PresenceStore.RemoveServer(jobId)
		end)
	end

	print(
		`[TravelService] mode={if isStub then "Stub" else "Live"} (PlaceId {game.PlaceId}) role={PlaceInfo.Role} attempts={TravelConfig.TeleportAttempts}`
	)
end

function TravelService.Start()
	setUp()
end

-- One player to the destination of `intent` (Portal, WorldGate, LobbyButton, ToLobby). Yields
-- until the travel ends and returns the outcome (Done, Refused, SaveFailed, TeleportFailed,
-- Lost, Left). Callers that must not wait wrap it in task.spawn.
function TravelService.Travel(player: Player, intent: string, options: any?): string
	assert(isPlayer(player), "TravelService.Travel: expected a Player")
	setUp()
	return core.travel(player.UserId, intent, options)
end

-- A group onto one server (MatchStart, Replay). options.accessCode is the reserved Arena server
-- matchmaking prepared; without one a new reserved server is opened. Returns "Started" or
-- "Refused"; each player's attempts then run in parallel.
function TravelService.TravelGroup(players: { Player }, intent: string, options: any?): string
	setUp()
	local userIds = {}
	for _, player in players do
		assert(isPlayer(player), "TravelService.TravelGroup: expected Players")
		table.insert(userIds, player.UserId)
	end
	return core.travelGroup(userIds, intent, options)
end

-- Lobby portal (#37): last visited world and zone.
function TravelService.ToSimulator(player: Player): string
	return TravelService.Travel(player, "Portal")
end

-- World gate (#105): the next world, first zone. The caller checks that the gate is open.
function TravelService.ToNextWorld(player: Player): string
	return TravelService.Travel(player, "WorldGate")
end

-- "Zur Lobby" after a match (7.21).
function TravelService.ToLobby(player: Player): string
	return TravelService.Travel(player, "ToLobby")
end

-- Matchmaking start (7.14) and "Nochmal" (7.21).
function TravelService.ToArena(players: { Player }, accessCode: string?): string
	return TravelService.TravelGroup(players, "MatchStart", { accessCode = accessCode })
end

function TravelService.Replay(players: { Player }, accessCode: string?): string
	return TravelService.TravelGroup(players, "Replay", { accessCode = accessCode })
end

-- The Simulator "Lobby" button (the TravelRequestLobby remote and the client API of
-- TravelController). Returns false when refused at once; otherwise the travel runs in the
-- background.
function TravelService.RequestLobby(player: Player): boolean
	assert(isPlayer(player), "TravelService.RequestLobby: expected a Player")
	setUp()
	local refused = PlaceInfo.Role ~= "Simulator" or core.isBusy(player.UserId)
	-- The core refuses (and logs) outside the Simulator and while travelling, before any yield.
	task.spawn(core.travel, player.UserId, "LobbyButton", nil)
	return not refused
end

function TravelService.IsTraveling(player: Player): boolean
	setUp()
	return core.isBusy(player.UserId)
end

return TravelService

--!strict
-- FindService (Simulator only, concept 7.7, 8.5, 6.5, ADR 0016): finds in the snow. The rules
-- are in the pure FindCore; this file wires them to the map (FindPoints, through ZoneService's
-- zone resolver), DataService, BallService, UpgradeService (Magnet), SellService, PopupService
-- and the FindUpdate remote.
--
-- Per player: every bound FindPoint holds at most one find of that player; a point empty for
-- Config.Finds.SpawnInterval gets a new one, rolled here. Each player sees only their own finds
-- (FindUpdate goes to that player only). The server picks a find up when its view of the
-- player's ball is within the Magnet radius, puts the value into the ball (SellService) and the
-- find into sim.collection at once. The finds stick in the ball until it is sold.
--
-- In Studio at PlaceId 0, switches on ServerScriptService and diagnostics on the Player support
-- playtests (FindStudio). Live servers skip all of it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FindsConfig = require(Config:WaitForChild("Finds")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local RarityConfig = require(Config:WaitForChild("Rarity")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local Rng = require(Shared:WaitForChild("Rng")) :: any

local FindCore = require(script:WaitForChild("FindCore"))
local FindPoints = require(script:WaitForChild("FindPoints"))
local FindStudio = require(script:WaitForChild("FindStudio"))

local PlaceServices = script.Parent
local BallService = require(PlaceServices:WaitForChild("BallService"))
local SellService = require(PlaceServices:WaitForChild("SellService"))
local UpgradeService = require(PlaceServices:WaitForChild("UpgradeService"))
local ZoneService = require(PlaceServices:WaitForChild("ZoneService"))
local Services = PlaceServices.Parent:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local NetService = require(Services:WaitForChild("NetService"))
local PopupService = require(Services:WaitForChild("PopupService"))

local REMOTE = "FindUpdate"
local MAGNET = "magnet"
local LOADED = "Loaded"

local FindService = {}

local isStudio = RunService:IsStudio()
local studioTools = isStudio and game.PlaceId == 0
local started = false
local names = FindsConfig.DiagnosticAttributes

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[FindService] {message}`)
	elseif isStudio then
		print(`[FindService] {message}`)
	end
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local core = FindCore.new({
	config = FindsConfig,
	findOdds = Rng.findOdds,
	pick = Rng.pick,
	findValue = Formulas.Economy.findValue,
	worldOf = Formulas.Zones.worldOf,
	-- One generator for finds only, so other rolls never shift this sequence.
	generator = Rng.new(),
	now = os.clock,
	unixTime = os.time,
	getProfile = function(userId: number): any
		local player = playerOf(userId)
		return if player then DataService.GetProfile(player) else nil
	end,
	isUnlocked = function(userId: number, zone: number): boolean
		local player = playerOf(userId)
		return player ~= nil and ZoneService.IsUnlocked(player, zone)
	end,
	addFindValue = function(userId: number, value: number): (boolean, string?)
		local player = playerOf(userId)
		if player == nil then
			return false, FindCore.Refusal.NotLoaded
		end
		return SellService.AddFindValue(player, value)
	end,
	log = log,
})

-- Every server: the ball effect of the player's titles (client contract, Config.Finds).
local function publishEffect(player: Player)
	local profile = DataService.GetProfile(player)
	local effect = if profile then FindCore.ballEffectOf(FindsConfig, profile) else nil
	player:SetAttribute(FindsConfig.BallEffectAttribute, effect)
end

local function send(player: Player, ...: any)
	(NetService.getRemote(REMOTE) :: any):FireClient(player, ...)
end

-- Every server: the client learns only about this player's own finds.
local function onEvent(event: any)
	local player = playerOf(event.userId)
	if player == nil or player.Parent ~= Players then
		return
	end
	local kind = event.kind
	if kind == "Spawn" then
		local point = event.point :: any
		send(player, "Spawn", event.slot, event.findId, Vector3.new(point.x, point.y, point.z))
	elseif kind == "Remove" then
		send(player, "Remove", event.slot)
	elseif kind == "Collect" then
		send(player, "Collect", event.slot, event.findId)
		local item = FindsConfig.Items[event.findId :: string]
		if item and item.PopupKey and FindsConfig.PopupRarities[event.rarity :: string] then
			PopupService.show(player, item.PopupKey)
		end
		if event.newTitle then
			PopupService.show(player, FindsConfig.TitlePopupKey)
			publishEffect(player)
		end
	elseif kind == "ClearBall" then
		send(player, "ClearBall")
	elseif kind == "Reset" then
		send(player, "Reset")
	end
end

local function describePoints(): string
	local perZone: { [number]: number } = {}
	local zones: { number } = {}
	local points = core.points()
	for _, point in points do
		if perZone[point.zone] == nil then
			perZone[point.zone] = 0
			table.insert(zones, point.zone)
		end
		perZone[point.zone] += 1
	end
	table.sort(zones)
	local parts: { string } = {}
	for _, zone in zones do
		table.insert(parts, `{zone}:{perZone[zone]}`)
	end
	return `points={#points} zones={table.concat(parts, ",")}`
end

local function setUpStudio()
	core.subscribe(function(event: any)
		local player = playerOf(event.userId)
		if player == nil then
			return
		end
		local text = FindStudio.writeDiagnostics(player, names, event, {
			spawned = core.spawned(event.userId),
			ball = core.ballFinds(event.userId),
			profile = DataService.GetProfile(player),
		}, os.clock())
		print(`[FindService] {player.Name} ({event.userId}) {text}`)
	end)
	FindStudio.bind(ServerScriptService, {
		setForce = function(player: Player, force: any)
			core.setForce(player.UserId, force)
		end,
		setTestPoints = function(enabled: boolean): string
			return FindStudio.setTestPoints(
				Workspace:FindFirstChild(MapConfig.FolderName),
				MapConfig,
				FindsConfig,
				MapConfig.Tags.FindPoint,
				enabled,
				function(instance: Instance, tag: string)
					CollectionService:AddTag(instance, tag)
				end
			)
		end,
		respawnNow = function(player: Player): number
			return core.spawnNow(player.UserId)
		end,
	}, RarityConfig.Order)
end

local function activate(player: Player)
	if studioTools then
		core.setForce(player.UserId, FindStudio.forceFor(ServerScriptService, player, RarityConfig.Order))
	end
	core.activate(player.UserId)
	publishEffect(player)
end

-- Last Magnet radius written per player (Studio diagnostics, written on change).
local magnetSent: { [Player]: number } = {}

local function pickup(player: Player)
	local part = BallService.GetBallPart(player)
	local magnet = UpgradeService.GetEffect(player, MAGNET)
	if studioTools and magnetSent[player] ~= magnet then
		magnetSent[player] = magnet
		player:SetAttribute(names.MagnetRadius, magnet)
	end
	if part == nil then
		return
	end
	local position = part.Position
	core.pickup(player.UserId, {
		x = position.X,
		y = position.Y,
		z = position.Z,
		radius = part.Size.X / 2,
	}, magnet, BallService.IsHeld(player))
end

function FindService.Start()
	if started then
		return
	end
	started = true

	NetService.Start()
	core.subscribe(onEvent)
	if studioTools then
		setUpStudio()
	end

	local points = FindPoints.start({
		map = MapConfig,
		zoneOf = ZoneService.ZoneOfInstance,
		onAdded = function(instance: Instance, zone: number, position: Vector3)
			local slot = core.addPoint(instance, zone, position.X, position.Y, position.Z, instance:GetFullName())
			log("info", `point bound {instance:GetFullName()} zone={zone} slot={slot}`)
			if studioTools then
				ServerScriptService:SetAttribute(names.PointsState, describePoints())
			end
		end,
		onRemoved = function(instance: Instance)
			core.removePoint(instance)
			if studioTools then
				ServerScriptService:SetAttribute(names.PointsState, describePoints())
			end
		end,
	})

	-- A sale empties the ball, so its finds no longer stick in it (owner decision 2026-11-10).
	SellService.Subscribe(function(event: any)
		if event.kind == "Sale" then
			core.clearBall(event.userId)
		end
	end)

	DataService.LoadStatusChanged:Connect(function(player: Player, status: string)
		if status == LOADED then
			activate(player)
		else
			core.deactivate(player.UserId)
			player:SetAttribute(FindsConfig.BallEffectAttribute, nil)
		end
	end)
	for _, player in Players:GetPlayers() do
		if DataService.GetProfile(player) ~= nil then
			activate(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		-- 6.5: the finds in the ball are lost on leaving; the collection is already in the profile.
		core.forget(player.UserId)
		magnetSent[player] = nil
	end)

	local spawnClock, pickupClock = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		spawnClock += dt
		pickupClock += dt
		if pickupClock >= FindsConfig.PickupCheckInterval then
			pickupClock = 0
			for _, player in Players:GetPlayers() do
				pickup(player)
			end
		end
		if spawnClock >= FindsConfig.SpawnCheckInterval then
			spawnClock = 0
			for _, player in Players:GetPlayers() do
				core.step(player.UserId)
			end
		end
	end)

	print(
		`[FindService] started points={points.count()} interval={FindsConfig.SpawnInterval}s studioSwitches={studioTools}`
	)
end

-- Finds stuck in the player's current ball (ids, in pickup order), for analytics (#43).
function FindService.GetBallFinds(player: Player): { string }
	return core.ballFinds(player.UserId)
end

-- Spawn, Remove, Collect, ClearBall, Reset and Refused events, for AnalyticsService (#43).
-- Returns an unsubscribe. Listeners must not yield.
function FindService.Subscribe(listener: (event: any) -> ()): () -> ()
	return core.subscribe(listener)
end

return FindService

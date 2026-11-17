--!strict
-- TutorialService: the onboarding hints of the first five minutes (concept 10.1, #42, ADR 0017).
-- Server-authoritative: it decides which hint shows and when a hint is done, from what the
-- server already knows (character positions, ball and balance attributes, sales, station
-- positions, portal attributes). The client only draws `TutorialActive` and reports the one
-- thing the server cannot see, the Upgrades window opening (TutorialHintDone remote).
--
-- State is the schema v1 profile table `tutorial` (no format change): `hints[id] = true`, and
-- `seenMultiArrow` for the Multiplayer arrow. It is saved with the normal saves (autosave, leave,
-- teleport); a hint is never set back to unseen except by the Studio reset.
--
-- Runs in the Lobby and the Simulator; in the Arena it does nothing (the first-match symbols of
-- 10.1 come with the match flow, 7.15).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BallConfig = require(Config:WaitForChild("Ball")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local SellConfig = require(Config:WaitForChild("Sell")) :: any
local TutorialConfig = require(Config:WaitForChild("Tutorial")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes")) :: any
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))
local TutorialAttributes = require(Shared:WaitForChild("TutorialAttributes"))

local CurrencyService = require(script.Parent:WaitForChild("CurrencyService")) :: any
local DataService = require(script.Parent:WaitForChild("DataService")) :: any
local NetService = require(script.Parent:WaitForChild("NetService")) :: any

local Stations = require(script:WaitForChild("Stations"))
local TutorialCore = require(script:WaitForChild("TutorialCore"))
local TutorialSwitches = require(script:WaitForChild("TutorialSwitches"))

local A = TutorialAttributes
local MULTI = TutorialConfig.MultiArrowHint
local REMOTE = "TutorialHintDone"

type Session = {
	showing: { [string]: string },
	active: { string },
	walked: number,
	lastX: number?,
	lastZ: number?,
	character: Model?,
	returnVisit: boolean,
}

local TutorialService = {}

local studioTools = RunService:IsStudio() and game.PlaceId == 0
local place = PlaceInfo.Role
local core = TutorialCore.new(TutorialConfig)
local sessions: { [Player]: Session } = {}
local stations: any = nil
local started = false

local function log(message: string)
	if studioTools then
		print(`[TutorialService] {message}`)
	end
end

local function tutorialOf(player: Player): any
	local profile = DataService.GetProfile(player)
	if type(profile) ~= "table" or type(profile.tutorial) ~= "table" then
		return nil
	end
	return profile.tutorial
end

local function publishDone(player: Player)
	local tutorial = tutorialOf(player)
	local text = if tutorial then A.encode(core.doneList(tutorial)) else ""
	if player:GetAttribute(A.DONE) ~= text then
		player:SetAttribute(A.DONE, text)
	end
end

local function publishActive(player: Player, active: { string })
	local text = A.encode(active)
	if player:GetAttribute(A.ACTIVE) ~= text then
		player:SetAttribute(A.ACTIVE, text)
		log(`{player.Name} ({player.UserId}) active={text}`)
	end
end

local function publishTarget(player: Player, target: Vector3?)
	local old = player:GetAttribute(A.TARGET)
	if target == nil then
		if old ~= nil then
			player:SetAttribute(A.TARGET, nil)
		end
	elseif typeof(old) ~= "Vector3" or (old - target).Magnitude > TutorialConfig.TargetEpsilon then
		player:SetAttribute(A.TARGET, target)
	end
end

local function noteChange(player: Player, text: string)
	log(`{player.Name} ({player.UserId}) {text}`)
	if studioTools then
		player:SetAttribute(A.LAST, text)
		player:SetAttribute(A.LAST_AT, Workspace:GetServerTimeNow())
	end
end

-- Sets a hint to done in the live profile; saved with the next save. Returns true when it changed.
local function markDone(player: Player, id: string, source: string): boolean
	local tutorial = tutorialOf(player)
	if not core.markDone(tutorial, id) then
		return false
	end
	noteChange(player, `{id} done source={source}`)
	local session = sessions[player]
	if session then
		session.showing, session.active = core.select(place, tutorial, {}, session.showing)
		publishActive(player, session.active)
	end
	publishDone(player)
	return true
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function newSession(player: Player): Session
	local tutorial = tutorialOf(player)
	-- A Lobby load is a later visit once the first portal travel has set seenSingleArrow
	-- (ADR 0015). The travel of this session sets it too, but that is still the first visit.
	local returnVisit = place == "Lobby" and tutorial ~= nil and tutorial.seenSingleArrow == true
	if studioTools then
		player:SetAttribute(A.RETURN_VISIT, returnVisit)
		player:SetAttribute(A.WALKED, 0)
	end
	return { showing = {}, active = {}, walked = 0, returnVisit = returnVisit }
end

local function zoneUnlocked(player: Player, zone: number): boolean
	local profile = DataService.GetProfile(player)
	local sim = type(profile) == "table" and profile.sim
	return type(sim) == "table" and type(sim.unlockedZones) == "table" and sim.unlockedZones[tostring(zone)] == true
end

local function coins(player: Player): number
	local value = CurrencyService.GetCoins(player)
	return if type(value) == "number" then value else 0
end

-- Conditions and the World-channel targets of this check, from server state only.
local function facts(player: Player, root: BasePart?): ({ [string]: boolean }, { [string]: Vector3 })
	local eligible: { [string]: boolean } = {}
	local targets: { [string]: Vector3 } = {}
	if place == "Lobby" then
		eligible.LobbyMove = root ~= nil
		local portal = Workspace:GetAttribute(LobbyAttributes.PORTAL_POSITION_PREFIX .. "Multiplayer")
		if typeof(portal) == "Vector3" then
			targets[MULTI] = portal
			eligible[MULTI] = sessions[player].returnVisit
		end
		return eligible, targets
	end

	eligible.ZoneMove = root ~= nil
	local anchor = player:GetAttribute(BallConfig.PlayerScaleAnchorAttribute)
	if typeof(anchor) == "Vector3" then
		targets.MaxScale = anchor
		eligible.MaxScale = player:GetAttribute(BallConfig.PlayerIsMaxAttribute) == true
	end
	eligible.UpgradesButton = true
	local balance = coins(player)
	if root then
		local egg = stations.nearest(
			stations.inZone(MapConfig.Tags.EggStation, Formulas.Pets.eggZone(TutorialConfig.EggIndex)),
			root.Position
		)
		if egg and egg.PrimaryPart then
			targets.EggStation = egg.PrimaryPart.Position
			eligible.EggStation = balance >= Formulas.Pets.eggPrice(TutorialConfig.EggIndex)
		end
		local barriers = stations.inZone(MapConfig.Tags.Barrier, TutorialConfig.BarrierZone)
		eligible.BarrierPulse = #barriers > 0
			and balance >= Formulas.Zones.barrierPrice(TutorialConfig.BarrierZone)
			and not zoneUnlocked(player, TutorialConfig.BarrierZone + 1)
	end
	return eligible, targets
end

-- The actions that end a showing hint and that the server sees itself.
local function checkActions(player: Player, session: Session, root: BasePart?)
	local active = session.active
	local controls = if place == "Lobby" then "LobbyMove" else "ZoneMove"
	if root then
		if session.character ~= player.Character then
			session.character = player.Character
			session.lastX, session.lastZ = nil, nil
		end
		local position = root.Position
		if table.find(active, controls) then
			session.walked = core.walk(session.walked, session.lastX, session.lastZ, position.X, position.Z)
			if studioTools then
				player:SetAttribute(A.WALKED, math.floor(session.walked * 10) / 10)
			end
			if core.moved(session.walked) then
				markDone(player, controls, "Moved")
			end
		end
		session.lastX, session.lastZ = position.X, position.Z
	end

	if place == "Lobby" then
		local portal = player:GetAttribute(LobbyAttributes.PORTAL_MODE)
		if table.find(active, MULTI) and type(portal) == "string" and portal ~= "" then
			-- Walking into either portal is the choice the arrow is about (ADR 0017).
			markDone(player, MULTI, `Portal{portal}`)
		end
		return
	end

	if zoneUnlocked(player, TutorialConfig.BarrierZone + 1) then
		markDone(player, "BarrierPulse", "Unlocked")
	end
	if root and table.find(active, "EggStation") then
		local zone = Formulas.Pets.eggZone(TutorialConfig.EggIndex)
		local _, distance = stations.nearest(stations.inZone(MapConfig.Tags.EggStation, zone), root.Position)
		if distance <= TutorialConfig.EggReachDistance then
			markDone(player, "EggStation", "Reached")
		end
	end
	if root and table.find(active, "BarrierPulse") then
		local barriers = stations.inZone(MapConfig.Tags.Barrier, TutorialConfig.BarrierZone)
		local _, distance = stations.nearest(barriers, root.Position)
		if distance <= TutorialConfig.BarrierReachDistance then
			markDone(player, "BarrierPulse", "WalkedInto")
		end
	end
end

local function step(player: Player)
	local tutorial = tutorialOf(player)
	local session = sessions[player]
	if tutorial == nil or session == nil or DataService.GetLoadStatus(player) ~= "Loaded" then
		publishActive(player, {})
		publishTarget(player, nil)
		return
	end
	local root = rootOf(player)
	checkActions(player, session, root)
	local eligible, targets = facts(player, root)
	local before = A.encode(session.active)
	session.showing, session.active = core.select(place, tutorialOf(player), eligible, session.showing)
	local after = A.encode(session.active)
	if after ~= before then
		for _, id in session.active do
			if table.find(string.split(before, ","), id) == nil then
				noteChange(player, `{id} shown`)
			end
		end
	end
	publishActive(player, session.active)
	local world = session.showing.World
	publishTarget(player, if world then targets[world] else nil)
	publishDone(player)
end

local lastStatus: { [Player]: string } = {}

local function onStatus(player: Player, status: string)
	local previous = lastStatus[player]
	lastStatus[player] = status
	if status == "Loaded" then
		-- Teleported -> Loaded is the session resumed after a failed teleport (or the Studio stub,
		-- ADR 0011): the same visit, so the session and its return-visit flag stay. Every other
		-- way to Loaded is a load from the store, i.e. a (re)join.
		if not (previous == "Teleported" and sessions[player]) then
			sessions[player] = newSession(player)
		end
	elseif status ~= "Teleported" then
		sessions[player] = nil
	end
	step(player)
end

-- The client says the Upgrades window opened. Accepted only for a reportable id that is showing
-- for this player; the server only ever sets a known id to done.
local function onReport(player: Player, id: string)
	local session = sessions[player]
	local ok, refusal = core.checkReport(id, if session then session.active else {})
	if not ok then
		if studioTools then
			player:SetAttribute(A.REFUSALS, ((player:GetAttribute(A.REFUSALS) :: number?) or 0) + 1)
		end
		noteChange(player, `{id} refused {refusal} source=Client`)
		return
	end
	markDone(player, id, "Client")
end

local function resetFor(player: Player): string
	local tutorial = tutorialOf(player)
	if not core.reset(tutorial) then
		return "no loaded profile"
	end
	sessions[player] = newSession(player)
	noteChange(player, "reset source=Studio")
	step(player)
	return "hints, seenMultiArrow and firstMatchHints reset (saved with the next save)"
end

function TutorialService.Start()
	if started then
		return
	end
	started = true
	if place ~= "Lobby" and place ~= "Simulator" then
		print(`[TutorialService] started place={place} inactive (first-match hints come with 7.15)`)
		return
	end

	if place == "Simulator" then
		stations = Stations.new({
			map = MapConfig,
			isZone = Formulas.Zones.isZone,
			worldOf = Formulas.Zones.worldOf,
			worldIndex = PlaceInfo.WorldIndex :: number,
		})
		-- The first sale ends the scale hint (and opens the way to the Upgrades hint). Listeners
		-- must not yield; markDone does not.
		CurrencyService.Subscribe(function(event: any)
			if event.kind == "Earn" and event.reason == SellConfig.CoinReason then
				local player = Players:GetPlayerByUserId(event.userId)
				if player then
					markDone(player, "MaxScale", "Sale")
				end
			end
		end)
	end

	NetService.handle(REMOTE, onReport)
	DataService.LoadStatusChanged:Connect(onStatus)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		lastStatus[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.GetLoadStatus(player) == "Loaded" and sessions[player] == nil then
			sessions[player] = newSession(player)
		end
	end

	if studioTools then
		TutorialSwitches.bind(ServerScriptService, {
			map = MapConfig,
			test = TutorialConfig.Test,
			isZone = Formulas.Zones.isZone,
			worldOf = Formulas.Zones.worldOf,
			worldIndex = if place == "Simulator" then PlaceInfo.WorldIndex else nil,
			log = log,
		}, { reset = resetFor })
	end

	task.spawn(function()
		while true do
			task.wait(TutorialConfig.CheckInterval)
			for _, player in Players:GetPlayers() do
				local ok, problem = pcall(step, player)
				if not ok then
					warn(`[TutorialService] check for {player.Name} failed: {problem}`)
				end
			end
		end
	end)

	print(
		`[TutorialService] started place={place} hints={#TutorialConfig.Order} remote={REMOTE} studioSwitches={studioTools}`
	)
end

-- For the egg (#41) and barrier (#39) features: their purchase ends the hint at once
-- ("EggStation" on an egg purchase, "BarrierPulse" on the zone 2 unlock). True when it changed.
function TutorialService.MarkDone(player: Player, id: string, source: string): boolean
	return markDone(player, id, source)
end

return TutorialService

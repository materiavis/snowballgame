--!strict
-- BallService (Simulator only, concept 7.3, 7.4, ADR 0002): every player's snowball. Spawns it
-- in front of the character, gives the owning client network ownership (the client holds and
-- rolls it, see BallController), registers the ball collision groups and decides the size.
--
-- The size is never sent by a client. The server measures the ball's own movement and grows a
-- size fraction 0..1 within the current zone (BallStep, GrowthRules), which the zone optics turn
-- into the part's diameter and the concept's metres. There is no remote.
--
-- In Studio at PlaceId 0, switches on ServerScriptService set zone and size for playtests
-- (ADR 0002 "Playtest hooks"). Live servers skip all of it.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BallConfig = require(Config:WaitForChild("Ball")) :: any
local ZonesConfig = require(Config:WaitForChild("Zones")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any

local BallAttributes = require(script:WaitForChild("BallAttributes"))
local BallCore = require(script:WaitForChild("BallCore"))
local BallPart = require(script:WaitForChild("BallPart"))
local BallStep = require(script:WaitForChild("BallStep"))
local CollisionSetup = require(script:WaitForChild("CollisionSetup"))
local GrowthModifiers = require(script:WaitForChild("GrowthModifiers"))
local GrowthRules = require(script:WaitForChild("GrowthRules"))
local ObstacleRules = require(script:WaitForChild("ObstacleRules"))
local Obstacles = require(script:WaitForChild("Obstacles"))
local StudioSwitches = require(script:WaitForChild("StudioSwitches"))
local SurfaceService = require(script.Parent:WaitForChild("SurfaceService"))

local MAX_PART_SIZE = 2048 -- Roblox engine limit per axis

type BallState = BallStep.BallState

local BallService = {}

local studioTools = RunService:IsStudio() and game.PlaceId == 0

local core = BallCore.new(BallConfig, ZonesConfig, Formulas.Zones.zoneOptics)
local rules = GrowthRules.new(BallConfig, Formulas.Zones.maxSize)
local modifiers = GrowthModifiers.new(Formulas.Upgrades.effect)
local obstacleRules = ObstacleRules.new(BallConfig)
local obstacles = Obstacles.new(BallConfig, obstacleRules, studioTools)
local attributes = BallAttributes.new(BallConfig, rules, studioTools)
local states: { [Player]: BallState } = {}
local ballsFolder: Folder
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local ballPart = BallPart.new(BallConfig, core.holdDistance, groundParams)

local growthPaused = false
local started = false

-- Server view (ADR 0003): ground rays ignore every ball and every character.
local function refreshGroundFilter()
	local excluded: { Instance } = { ballsFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = excluded
end

local function assignOwner(state: BallState)
	local part = state.part
	if part:IsDescendantOf(workspace) and part:CanSetNetworkOwnership() then
		part:SetNetworkOwner(state.player)
	end
end

local function spawnPosition(root: BasePart, diameter: number): Vector3
	return ballPart.spawnPosition(root, diameter)
end

local function publish(state: BallState)
	attributes.publish(state, os.clock(), true)
end

local function createPart(state: BallState, diameter: number, position: Vector3): Part
	local part = ballPart.create(state.player, diameter, position, ballsFolder)
	part:SetAttribute(BallConfig.RecoveriesAttribute, state.recoveries)
	state.sentPart = {}
	return part
end

-- Puts the ball back in front of the character: first spawn after a destroy, respawn of the
-- character, fell off the map or stuck out of reach.
local function placeBall(state: BallState, root: BasePart)
	local diameter = core.visualDiameter(state.zone, state.fraction)
	local position = spawnPosition(root, diameter)
	local part = state.part
	if part.Parent then
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		part.Size = Vector3.one * diameter
		part.CFrame = CFrame.new(position)
	else
		state.part = createPart(state, diameter, position)
	end
	publish(state)
	state.lastPosition = position
	state.lastSampleTime = os.clock()
	state.wasGrounded = false
	state.outOfReachFor = 0
	-- Whatever the ball was placed on was not rolled into (ObstacleRules.evaluate). The first
	-- sample may not see the contact yet, so protection covers the samples right after it: a
	-- contact first seen while protected is remembered without a loss.
	state.contacts = nil
	state.protectedUntil = math.max(state.protectedUntil, os.clock() + BallConfig.CollisionProtection)
	assignOwner(state)
end

local function recover(state: BallState, root: BasePart, why: string)
	state.recoveries += 1
	placeBall(state, root)
	state.part:SetAttribute(BallConfig.RecoveriesAttribute, state.recoveries)
	if studioTools then
		print(`[BallService] {state.player.Name} ball put back in front ({why}), recoveries={state.recoveries}`)
	end
end

-- Applies the optics of the current zone and fraction to the part. `force` skips the step
-- check (zone change, Studio switch).
local function applyOptics(state: BallState, force: boolean)
	local part = state.part
	if not part.Parent then
		return
	end
	local target = core.visualDiameter(state.zone, state.fraction)
	local current = part.Size.X
	if not force and not core.shouldResize(current, target, state.fraction) then
		return
	end
	if math.abs(target - current) > 1e-6 then
		-- Move the centre by the change in radius so the bottom stays on the ground instead of
		-- the solver pushing a penetrating ball out (seen as a hop or jitter).
		local cframe = part.CFrame
		part.Size = Vector3.one * target
		part.CFrame = cframe + Vector3.new(0, (target - current) / 2, 0)
		-- Re-assert ownership after the server-side move so the client keeps simulating it.
		assignOwner(state)
	end
	publish(state)
end

local ballStep = BallStep.new({
	config = BallConfig,
	core = core,
	rules = rules,
	obstacleRules = obstacleRules,
	obstacles = obstacles,
	modifiers = modifiers,
	surfaces = SurfaceService,
	attributes = attributes,
	groundParams = groundParams,
	isPaused = function(): boolean
		return growthPaused
	end,
	recover = recover,
	applyOptics = applyOptics,
})

local function spawnBall(player: Player, root: BasePart, humanoid: Humanoid?)
	local zone = BallConfig.DefaultZone
	local diameter = core.visualDiameter(zone, 0)
	local position = spawnPosition(root, diameter)
	local state = BallStep.newState(player, root, humanoid, zone, SurfaceService.newTrack())
	state.lastPosition = position
	state.part = createPart(state, diameter, position)
	states[player] = state
	publish(state)
	assignOwner(state)
end

local function onPlayerAdded(player: Player)
	local function onCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		local foundHumanoid = character:WaitForChild("Humanoid", 10)
		if not root or player.Parent == nil or player.Character ~= character then
			return
		end
		local humanoid = if foundHumanoid and foundHumanoid:IsA("Humanoid") then foundHumanoid else nil
		refreshGroundFilter()
		local state = states[player]
		if state then
			state.root = root
			state.humanoid = humanoid
			placeBall(state, root)
		else
			spawnBall(player, root, humanoid)
		end
	end

	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		local state = states[player]
		if state then
			state.root = nil
			state.humanoid = nil
		end
		task.defer(refreshGroundFilter)
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if state then
		states[player] = nil
		state.part:Destroy()
	end
	task.defer(refreshGroundFilter)
end

local function setUpCollisions(): (boolean, string)
	local physics = CollisionSetup.fromPhysicsService(PhysicsService)
	CollisionSetup.apply(physics, BallConfig.CollisionGroups, BallConfig.CollisionRules)
	return CollisionSetup.check(physics, BallConfig.CollisionRules)
end

local function setZone(state: BallState, zone: number)
	state.zone = zone
	applyOptics(state, true)
end

local function setFraction(state: BallState, fraction: number)
	state.fraction = fraction
	-- A new measurement of the time to the maximum starts from here.
	state.growthStartedAt = nil
	state.measuredTimeToMax = nil
	applyOptics(state, true)
end

local function setUpStudio()
	StudioSwitches.bind(ServerScriptService, {
		targets = function(targetUserId: number): { any }
			local result = {}
			for player, state in states do
				if targetUserId == 0 or player.UserId == targetUserId then
					table.insert(result, state)
				end
			end
			return result
		end,
		isZone = Formulas.Zones.isZone,
		isFraction = core.isFraction,
		zoneCount = ZonesConfig.ZoneCount,
		setZone = setZone,
		setFraction = setFraction,
		recover = function(state: BallState)
			if state.root and state.root.Parent then
				recover(state, state.root, "switch")
			end
		end,
		setPaused = function(paused: boolean)
			growthPaused = paused
		end,
		simulateCollision = function(state: BallState)
			ballStep.applyCollision(state, os.clock())
			applyOptics(state, true)
		end,
		moveCharacterAway = function(state: BallState, studs: number)
			local root = state.root
			if not root or not root.Parent then
				return
			end
			local away = root.Position - state.part.Position
			local direction = Vector3.new(away.X, 0, away.Z)
			if direction.Magnitude < 1e-3 then
				direction = Vector3.new(0, 0, 1)
			end
			root.CFrame = root.CFrame + direction.Unit * studs
		end,
		clearTrack = function(state: BallState)
			state.track.clear()
		end,
		describe = function(state: BallState): string
			local fraction = string.format("%.3f", state.fraction)
			local diameter = string.format("%.2f", state.part.Size.X)
			local metres = string.format("%.2f", rules.sizeMetres(state.zone, state.fraction))
			return `{state.player.Name} zone={state.zone} fraction={fraction} diameter={diameter} metres={metres}`
		end,
	})
end

function BallService.Start()
	if started then
		return
	end
	started = true

	assert(ZonesConfig.VisualCap <= MAX_PART_SIZE, "Config.Zones.VisualCap exceeds the Roblox part size limit")
	assert(Formulas.Zones.isZone(BallConfig.DefaultZone), "Config.Ball.DefaultZone must be a valid zone")
	-- The ball moves at the character's walk speed, so the base speed must be fully counted.
	assert(
		BallConfig.WalkSpeed < BallConfig.MaxCountedSpeed,
		"Config.Ball.WalkSpeed must be below MaxCountedSpeed, or base pushing would not grow the ball fully"
	)
	assert(BallConfig.HoldGap > 0, "Config.Ball.HoldGap must be positive")
	-- Growth is checked at the hold distance, so the range has to include it.
	assert(BallConfig.GrowthRange > BallConfig.HoldGap, "Config.Ball.GrowthRange must be above HoldGap")

	local collisionsOk, collisionText = setUpCollisions()
	if not collisionsOk then
		warn(`[BallService] collision rules do not hold: {collisionText}`)
	end

	local folder = Instance.new("Folder")
	folder.Name = BallConfig.FolderName
	folder.Parent = workspace
	ballsFolder = folder
	refreshGroundFilter()
	obstacles.start(folder)

	if studioTools then
		setUpStudio()
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < BallConfig.SampleInterval then
			return
		end
		accumulator = 0
		local now = os.clock()
		for _, state in states do
			ballStep.update(state, now)
		end
	end)

	print(
		`[BallService] started collisions={if collisionsOk then "ok" else "FAILED"} {collisionText} studioSwitches={studioTools}`
	)
end

-- Zone of the player's ball. ZoneService (#29/#39) calls SetZone; until then it is
-- Config.Ball.DefaultZone. Returns false for an unknown player or an invalid zone.
function BallService.SetZone(player: Player, zone: number): boolean
	local state = states[player]
	if state == nil or not Formulas.Zones.isZone(zone) then
		return false
	end
	setZone(state, zone)
	return true
end

function BallService.GetZone(player: Player): number?
	local state = states[player]
	return if state then state.zone else nil
end

-- Size fraction 0..1 within the current zone, decided here.
function BallService.GetSizeFraction(player: Player): number?
	local state = states[player]
	return if state then state.fraction else nil
end

-- Real size in metres (concept 7.4), the value selling (7.5) reads.
function BallService.GetSizeMetres(player: Player): number?
	local state = states[player]
	return if state then rules.sizeMetres(state.zone, state.fraction) else nil
end

return BallService

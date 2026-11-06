--!strict
-- BallService (Simulator only, concept 7.3, ADR 0002): every player's snowball. Spawns it in
-- front of the character, gives the owning client network ownership (the client holds and
-- rolls it, see BallController), registers the ball collision groups and decides the size.
--
-- The size is never sent by a client. The server measures the ball's own movement, grows a
-- size fraction 0..1 within the current zone (interim until #34) and turns it into the part's
-- diameter through the zone optics. There is no remote.
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

local BallCore = require(script:WaitForChild("BallCore"))
local CollisionSetup = require(script:WaitForChild("CollisionSetup"))

local MAX_PART_SIZE = 2048 -- Roblox engine limit per axis

-- Studio-only switch names (the playtest contract, ADR 0002).
local TARGET_SWITCH = "BallTargetUserId"
local ZONE_SWITCH = "BallSetZone"
local FRACTION_SWITCH = "BallSetSizeFraction"
local PAUSE_SWITCH = "BallGrowthPaused"
local RECOVER_SWITCH = "BallRecover"
local FRACTION_IDLE = -1

type BallState = {
	player: Player,
	part: Part,
	root: BasePart?,
	zone: number,
	fraction: number,
	lastPosition: Vector3,
	lastSampleTime: number,
	wasGrounded: boolean,
	outOfReachFor: number,
	recoveries: number,
}

local BallService = {}

local core = BallCore.new(BallConfig, ZonesConfig, Formulas.Zones.zoneOptics)
local states: { [Player]: BallState } = {}
local ballsFolder: Folder
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local studioTools = RunService:IsStudio() and game.PlaceId == 0
local growthPaused = false
local started = false

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

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

-- Centre for a ball of the given diameter, on the ground at the hold distance in front of
-- the character, so it starts where the client holds it.
local function spawnPosition(root: BasePart, diameter: number): Vector3
	local look = flat(root.CFrame.LookVector)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	local radius = diameter / 2
	local spot = root.Position + look.Unit * core.holdDistance(diameter)
	local height = BallConfig.SpawnGroundSearchHeight
	local origin = Vector3.new(spot.X, root.Position.Y + height, spot.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -height * 4, 0), groundParams)
	local groundY = if result then result.Position.Y else root.Position.Y - 3
	return Vector3.new(spot.X, groundY + radius, spot.Z)
end

local function publish(state: BallState)
	local part = state.part
	part:SetAttribute(BallConfig.ZoneAttribute, state.zone)
	-- Rounded so the attribute does not replicate float noise; the server keeps the exact value.
	part:SetAttribute(BallConfig.SizeFractionAttribute, math.round(state.fraction * 1000) / 1000)
	part:SetAttribute(BallConfig.VisualDiameterAttribute, part.Size.X)
end

local function createPart(state: BallState, diameter: number, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "Ball_" .. state.player.UserId
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * diameter
	part.Material = Enum.Material.Snow
	part.Color = Color3.fromRGB(245, 248, 255)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CustomPhysicalProperties = PhysicalProperties.new(
		BallConfig.Density,
		BallConfig.Friction,
		BallConfig.Elasticity,
		BallConfig.FrictionWeight,
		BallConfig.ElasticityWeight
	)
	-- Server view: every ball is in Balls. Clients reassign locally (CollisionController).
	part.CollisionGroup = BallConfig.CollisionGroups.Balls
	part.CFrame = CFrame.new(position)
	part:SetAttribute(BallConfig.OwnerAttribute, state.player.UserId)
	part:SetAttribute(BallConfig.RecoveriesAttribute, state.recoveries)
	part.Parent = ballsFolder
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

local function isGrounded(part: BasePart): boolean
	local radius = part.Size.X / 2
	local length = radius + BallConfig.GroundCheckMargin + radius * BallConfig.GroundCheckMarginPerRadius
	return workspace:Raycast(part.Position, Vector3.new(0, -length, 0), groundParams) ~= nil
end

local function updateBall(state: BallState, now: number)
	local part = state.part
	local root = state.root
	local rootAlive = root ~= nil and root.Parent ~= nil
	if not part.Parent or part.Position.Y < BallConfig.ResetBelowY then
		if root and rootAlive then
			recover(state, root, if part.Parent then "fell" else "missing")
		end
		return
	end

	local position = part.Position
	local elapsed = now - state.lastSampleTime

	if root and rootAlive then
		local horizontal = flat(position - root.Position).Magnitude
		if core.isOutOfReach(horizontal, part.Size.X) then
			state.outOfReachFor += elapsed
			if core.leashExpired(state.outOfReachFor) then
				recover(state, root, "out of reach")
				return
			end
		else
			state.outOfReachFor = 0
		end
	end

	local grounded = isGrounded(part)
	if not growthPaused then
		local distance = (position - state.lastPosition).Magnitude
		state.fraction = core.grow(state.fraction, distance, elapsed, grounded and state.wasGrounded)
	end
	state.lastPosition = position
	state.lastSampleTime = now
	state.wasGrounded = grounded

	if grounded then
		applyOptics(state, false)
	end
end

local function spawnBall(player: Player, root: BasePart)
	local zone = BallConfig.DefaultZone
	local diameter = core.visualDiameter(zone, 0)
	local position = spawnPosition(root, diameter)
	local state: BallState = {
		player = player,
		part = nil :: any,
		root = root,
		zone = zone,
		fraction = 0,
		lastPosition = position,
		lastSampleTime = os.clock(),
		wasGrounded = false,
		outOfReachFor = 0,
		recoveries = 0,
	}
	state.part = createPart(state, diameter, position)
	states[player] = state
	publish(state)
	assignOwner(state)
end

local function onPlayerAdded(player: Player)
	local function onCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if not root or player.Parent == nil or player.Character ~= character then
			return
		end
		refreshGroundFilter()
		local state = states[player]
		if state then
			state.root = root
			placeBall(state, root)
		else
			spawnBall(player, root)
		end
	end

	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		local state = states[player]
		if state then
			state.root = nil
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
	local physics = {
		isRegistered = function(name: string): boolean
			return PhysicsService:IsCollisionGroupRegistered(name)
		end,
		register = function(name: string)
			PhysicsService:RegisterCollisionGroup(name)
		end,
		setCollidable = function(a: string, b: string, collides: boolean)
			PhysicsService:CollisionGroupSetCollidable(a, b, collides)
		end,
		areCollidable = function(a: string, b: string): boolean
			return PhysicsService:CollisionGroupsAreCollidable(a, b)
		end,
	}
	CollisionSetup.apply(physics, BallConfig.CollisionGroups, BallConfig.CollisionRules)
	return CollisionSetup.check(physics, BallConfig.CollisionRules)
end

local function setZone(state: BallState, zone: number)
	state.zone = zone
	applyOptics(state, true)
end

-- Studio switches. Targets: BallTargetUserId, or every player when it is 0.
local function studioTargets(): { BallState }
	local target = ServerScriptService:GetAttribute(TARGET_SWITCH)
	local result: { BallState } = {}
	for player, state in states do
		if type(target) ~= "number" or target == 0 or player.UserId == target then
			table.insert(result, state)
		end
	end
	return result
end

local function describe(state: BallState): string
	return `zone={state.zone} fraction={string.format("%.3f", state.fraction)} diameter={string.format(
		"%.2f",
		state.part.Size.X
	)}`
end

local function bindSwitch(name: string, idle: any, action: (value: any) -> ())
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, idle)
	end
	ServerScriptService:GetAttributeChangedSignal(name):Connect(function()
		local value = ServerScriptService:GetAttribute(name)
		if value == idle or value == nil then
			return
		end
		ServerScriptService:SetAttribute(name, idle)
		action(value)
	end)
end

local function setUpStudio()
	if ServerScriptService:GetAttribute(TARGET_SWITCH) == nil then
		ServerScriptService:SetAttribute(TARGET_SWITCH, 0)
	end
	bindSwitch(ZONE_SWITCH, 0, function(zone)
		if not Formulas.Zones.isZone(zone) then
			warn(`[BallService] {ZONE_SWITCH}: zone must be a whole number 1..{ZonesConfig.ZoneCount}, got {zone}`)
			return
		end
		for _, state in studioTargets() do
			setZone(state, zone)
			print(`[BallService] {state.player.Name} {ZONE_SWITCH} -> {describe(state)}`)
		end
	end)
	bindSwitch(FRACTION_SWITCH, FRACTION_IDLE, function(fraction)
		if not core.isFraction(fraction) then
			warn(`[BallService] {FRACTION_SWITCH}: fraction must be a number 0..1, got {fraction}`)
			return
		end
		for _, state in studioTargets() do
			state.fraction = fraction
			applyOptics(state, true)
			print(`[BallService] {state.player.Name} {FRACTION_SWITCH} -> {describe(state)}`)
		end
	end)
	bindSwitch(RECOVER_SWITCH, false, function(value)
		if value ~= true then
			return
		end
		for _, state in studioTargets() do
			if state.root and state.root.Parent then
				recover(state, state.root, "switch")
			end
		end
	end)
	if ServerScriptService:GetAttribute(PAUSE_SWITCH) == nil then
		ServerScriptService:SetAttribute(PAUSE_SWITCH, false)
	end
	ServerScriptService:GetAttributeChangedSignal(PAUSE_SWITCH):Connect(function()
		growthPaused = ServerScriptService:GetAttribute(PAUSE_SWITCH) == true
		print(`[BallService] {PAUSE_SWITCH}={growthPaused}`)
	end)
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

	local collisionsOk, collisionText = setUpCollisions()
	if not collisionsOk then
		warn(`[BallService] collision rules do not hold: {collisionText}`)
	end

	local folder = Instance.new("Folder")
	folder.Name = BallConfig.FolderName
	folder.Parent = workspace
	ballsFolder = folder
	refreshGroundFilter()

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
			updateBall(state, now)
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

-- Size fraction 0..1 within the current zone, decided here (interim growth until #34).
function BallService.GetSizeFraction(player: Player): number?
	local state = states[player]
	return if state then state.fraction else nil
end

return BallService

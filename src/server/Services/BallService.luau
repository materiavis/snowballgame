--!strict
-- Owns every player's snowball: spawning, network ownership, collision group and growth.
-- The owning client simulates the ball's physics (it pushes it), but the size is decided here
-- from distances measured on the server.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BallConfig"))

local MAX_PART_SIZE = 2048 -- Roblox engine limit per axis

type BallState = {
	player: Player,
	part: Part,
	internalSize: number, -- real diameter, keeps growing past the visual cap
	publishedSize: number, -- last value written to the size attribute / applied to the part
	lastPosition: Vector3,
	lastSampleTime: number,
	wasGrounded: boolean,
}

local BallService = {}

local states: { [Player]: BallState } = {}
local ballsFolder: Folder
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function physicalDiameter(internalSize: number): number
	return math.min(internalSize, BallConfig.VisualCapDiameter)
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Center position for a ball of the given diameter, resting on the ground in front of the character.
local function spawnPosition(root: BasePart, diameter: number): Vector3
	local radius = diameter / 2
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	local flat = root.Position + look.Unit * (radius + BallConfig.SpawnGapFromCharacter + 1)

	local origin = Vector3.new(flat.X, root.Position.Y + BallConfig.SpawnGroundSearchHeight, flat.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -BallConfig.SpawnGroundSearchHeight * 4, 0), groundParams)
	local groundY = if result then result.Position.Y else root.Position.Y - 3
	return Vector3.new(flat.X, groundY + radius, flat.Z)
end

local function assignOwner(state: BallState)
	local part = state.part
	if part:IsDescendantOf(workspace) and part:CanSetNetworkOwnership() then
		part:SetNetworkOwner(state.player)
	end
end

local function createPart(player: Player, internalSize: number, position: Vector3): Part
	local diameter = physicalDiameter(internalSize)
	local part = Instance.new("Part")
	part.Name = "Ball_" .. player.UserId
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
	part.CollisionGroup = BallConfig.CollisionGroup
	part.CFrame = CFrame.new(position)
	part:SetAttribute(BallConfig.OwnerAttribute, player.UserId)
	part:SetAttribute(BallConfig.SizeAttribute, internalSize)
	part.Parent = ballsFolder
	return part
end

-- Creates the ball part (first spawn, or after it was destroyed / fell off the map) next to the character.
local function placeBall(state: BallState, root: BasePart)
	local position = spawnPosition(root, physicalDiameter(state.publishedSize))
	if state.part.Parent then
		state.part.AssemblyLinearVelocity = Vector3.zero
		state.part.AssemblyAngularVelocity = Vector3.zero
		state.part.CFrame = CFrame.new(position)
	else
		state.part = createPart(state.player, state.publishedSize, position)
	end
	state.lastPosition = position
	state.lastSampleTime = os.clock()
	state.wasGrounded = false
	assignOwner(state)
end

local function spawnBall(player: Player, root: BasePart)
	if states[player] then
		return
	end
	local size = BallConfig.StartDiameter
	local position = spawnPosition(root, physicalDiameter(size))
	local state: BallState = {
		player = player,
		part = createPart(player, size, position),
		internalSize = size,
		publishedSize = size,
		lastPosition = position,
		lastSampleTime = os.clock(),
		wasGrounded = false,
	}
	states[player] = state
	assignOwner(state)
end

local function isGrounded(part: BasePart): boolean
	local radius = part.Size.X / 2
	local length = radius + BallConfig.GroundCheckMargin + radius * BallConfig.GroundCheckMarginPerRadius
	return workspace:Raycast(part.Position, Vector3.new(0, -length, 0), groundParams) ~= nil
end

-- Applies accumulated growth to the attribute and, below the cap, to the physical part.
local function applyGrowth(state: BallState)
	state.publishedSize = state.internalSize
	local part = state.part
	part:SetAttribute(BallConfig.SizeAttribute, state.internalSize)

	local newDiameter = physicalDiameter(state.internalSize)
	local oldDiameter = part.Size.X
	local added = newDiameter - oldDiameter
	if added <= 1e-3 then
		return
	end
	-- Raise the center by the added radius so the bottom stays on the ground instead of the
	-- solver pushing a penetrating ball out (which shows up as a hop or jitter).
	local cframe = part.CFrame
	part.Size = Vector3.one * newDiameter
	part.CFrame = cframe + Vector3.new(0, added / 2, 0)
	-- Re-assert ownership after the server-side move so the pushing client keeps simulating the ball.
	assignOwner(state)
end

local function updateBall(state: BallState, now: number)
	local part = state.part
	if not part.Parent or part.Position.Y < BallConfig.ResetBelowY then
		local root = getRootPart(state.player)
		if root then
			placeBall(state, root)
		end
		return
	end

	local position = part.Position
	local elapsed = now - state.lastSampleTime
	local grounded = isGrounded(part)
	local distance = (position - state.lastPosition).Magnitude

	-- Only rolling on the ground counts: both samples grounded, real movement, plausible speed.
	if
		grounded
		and state.wasGrounded
		and elapsed > 0
		and distance >= BallConfig.MinDistancePerSample
		and distance / elapsed <= BallConfig.MaxCountedSpeed
	then
		state.internalSize += distance * BallConfig.GrowthPerStud
	end

	state.lastPosition = position
	state.lastSampleTime = now
	state.wasGrounded = grounded

	if grounded and state.internalSize - state.publishedSize >= BallConfig.GrowthStep then
		applyGrowth(state)
	end
end

local function refreshGroundFilter()
	local excluded: { Instance } = { ballsFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = excluded
end

local function onPlayerAdded(player: Player)
	local function onCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if not root or player.Parent == nil then
			return
		end
		refreshGroundFilter()
		spawnBall(player, root)
	end

	player.CharacterAdded:Connect(onCharacter)
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
end

local function setupCollisionGroup()
	local group = BallConfig.CollisionGroup
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
	PhysicsService:CollisionGroupSetCollidable(group, group, false)
end

function BallService.Start()
	assert(BallConfig.VisualCapDiameter <= MAX_PART_SIZE, "BallConfig.VisualCapDiameter exceeds Roblox part size limit")
	assert(BallConfig.StartDiameter > 0, "BallConfig.StartDiameter must be positive")
	assert(
		BallConfig.PushMaxSpeed < BallConfig.MaxCountedSpeed,
		"BallConfig.PushMaxSpeed must be below MaxCountedSpeed, or legit pushing would not grow the ball"
	)

	setupCollisionGroup()

	local folder = Instance.new("Folder")
	folder.Name = BallConfig.FolderName
	folder.Parent = workspace
	ballsFolder = folder

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
		refreshGroundFilter()
		local now = os.clock()
		for _, state in states do
			updateBall(state, now)
		end
	end)
end

return BallService

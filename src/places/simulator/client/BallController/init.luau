--!strict
-- BallController (Simulator only, concept 7.3, ADR 0002): holds the own ball directly in
-- front of the character in walking direction. Steering is walking; there is no ball button,
-- so the touch joystick alone steers it.
--
-- The server makes this client the ball's network owner, so a local VectorForce moves it.
-- The force only acts sideways (x/z); gravity and ground friction make the ball roll. The
-- ball keeps pace with the character, so push speed follows Humanoid.WalkSpeed, which the
-- server sets. This client never sends a size, a distance or a position to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any
local HoldMath = require(script:WaitForChild("HoldMath"))

local localPlayer = Players.LocalPlayer
local hold = HoldMath.new(BallConfig)

local BallController = {}

local myBall: BasePart? = nil
local pushForce: VectorForce? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
-- Unit hold direction on the ground plane: the last walking direction. The ball swings
-- around the character towards root + held * hold distance (HoldMath).
local heldX, heldZ = 0, -1
local started = false

-- Starts the hold direction where the ball already is, so it does not jump on (re)spawn.
local function resetHeldDirection()
	local ball, rootPart = myBall, root
	if not ball or not rootPart then
		return
	end
	local offset = ball.Position - rootPart.Position
	local x, z = offset.X, offset.Z
	local length = math.sqrt(x * x + z * z)
	if length < 1e-3 then
		local look = rootPart.CFrame.LookVector
		x, z = look.X, look.Z
		length = math.sqrt(x * x + z * z)
	end
	if length > 1e-3 then
		heldX, heldZ = x / length, z / length
	end
end

local function attachPushForce(ball: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "PushAttachment"
	attachment.Parent = ball

	local force = Instance.new("VectorForce")
	force.Name = "PushForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = ball

	myBall = ball
	pushForce = force
	resetHeldDirection()
end

local function onBallAdded(child: Instance)
	if child:IsA("BasePart") and child:GetAttribute(BallConfig.OwnerAttribute) == localPlayer.UserId then
		attachPushForce(child)
	end
end

local function onBallRemoved(child: Instance)
	if child == myBall then
		myBall = nil
		pushForce = nil
	end
end

local function onCharacter(character: Model)
	humanoid = nil
	root = nil
	local foundHumanoid = character:WaitForChild("Humanoid", 10)
	local foundRoot = character:WaitForChild("HumanoidRootPart", 10)
	if localPlayer.Character ~= character then
		return
	end
	if foundHumanoid and foundHumanoid:IsA("Humanoid") and foundRoot and foundRoot:IsA("BasePart") then
		humanoid = foundHumanoid
		root = foundRoot
		resetHeldDirection()
	end
end

local function step()
	local ball, force = myBall, pushForce
	if not ball or not force or not ball.Parent then
		return
	end
	local position = ball.Position
	local velocity = ball.AssemblyLinearVelocity
	local h, rootPart = humanoid, root
	local ax, az
	if h and rootPart and rootPart.Parent and h.Health > 0 then
		local walkSpeed = h.WalkSpeed
		local move = h.MoveDirection
		local mx, mz = move.X, move.Z
		local moving = math.sqrt(mx * mx + mz * mz)
		if moving > BallConfig.MoveDeadzone then
			heldX, heldZ = mx / moving, mz / moving
		end
		local rootPosition = rootPart.Position
		local rootVelocity = rootPart.AssemblyLinearVelocity
		local wantX, wantZ = hold.desiredVelocity(
			position.X - rootPosition.X,
			position.Z - rootPosition.Z,
			heldX,
			heldZ,
			hold.holdDistance(ball.Size.X),
			rootVelocity.X,
			rootVelocity.Z,
			walkSpeed
		)
		ax, az = hold.acceleration(wantX, wantZ, velocity.X, velocity.Z)
	else
		-- No living character: brake the ball where it is.
		ax, az = hold.acceleration(0, 0, velocity.X, velocity.Z)
	end
	local mass = ball.AssemblyMass
	force.Force = Vector3.new(ax * mass, 0, az * mass)
end

function BallController.Start()
	if started then
		return
	end
	started = true

	localPlayer.CharacterAdded:Connect(onCharacter)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end

	local folder = workspace:WaitForChild(BallConfig.FolderName)
	folder.ChildAdded:Connect(onBallAdded)
	folder.ChildRemoved:Connect(onBallRemoved)
	for _, child in folder:GetChildren() do
		onBallAdded(child)
	end

	RunService.PreSimulation:Connect(step)
	print(`[BallController] started ownBall={myBall ~= nil}`)
end

return BallController

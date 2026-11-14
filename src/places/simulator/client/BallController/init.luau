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

-- Client view only (ADR 0002 "Playtest hooks"): how many server recoveries the hold followed,
-- and how often the rebound brake (#97) started.
local HOLD_RESETS_ATTRIBUTE = "BallHoldResets"
local REBOUND_BRAKES_ATTRIBUTE = "BallReboundBrakes"

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
-- os.clock() when the server last put the own ball back (seen through its replicated
-- Recoveries attribute); nil = none yet.
local recoveredAt: number? = nil
local holdResets = 0
local reboundBrakes = 0
local braking = false
local started = false

-- Starts the hold direction where the ball already is, so it does not jump on (re)spawn.
local function resetHeldDirection()
	local ball, rootPart = myBall, root
	if not ball or not rootPart then
		return
	end
	local look = rootPart.CFrame.LookVector
	local fallbackX, fallbackZ = hold.directionTo(look.X, look.Z, heldX, heldZ)
	local offset = ball.Position - rootPart.Position
	heldX, heldZ = hold.directionTo(offset.X, offset.Z, fallbackX, fallbackZ)
end

-- The server wrote a new Recoveries or Placements count: it moved the ball. Only the server
-- writes these attributes, and they replicate on live servers too, so nothing is sent or
-- decided here.
local function onRecovered()
	recoveredAt = os.clock()
	holdResets += 1
	localPlayer:SetAttribute(HOLD_RESETS_ATTRIBUTE, holdResets)
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
	-- A new part also follows for the reset window: after a `missing` recovery the server
	-- creates it and sets the count in the same frame, so no attribute change may arrive.
	recoveredAt = os.clock()
	resetHeldDirection()
	local function onServerMove()
		if ball == myBall then
			onRecovered()
		end
	end
	ball:GetAttributeChangedSignal(BallConfig.RecoveriesAttribute):Connect(onServerMove)
	-- Moves that are not recoveries (respawn, Studio switch BallPlaceBehindObstacle) as well.
	ball:GetAttributeChangedSignal(BallConfig.PlacementsAttribute):Connect(onServerMove)
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
		local rootPosition = rootPart.Position
		local rx, rz = position.X - rootPosition.X, position.Z - rootPosition.Z
		heldX, heldZ =
			hold.nextHeldDirection(heldX, heldZ, move.X, move.Z, rx, rz, hold.followsBall(os.clock(), recoveredAt))
		local rootVelocity = rootPart.AssemblyLinearVelocity
		local distance = hold.holdDistance(ball.Size.X)
		local wantX, wantZ =
			hold.desiredVelocity(rx, rz, heldX, heldZ, distance, rootVelocity.X, rootVelocity.Z, walkSpeed)
		local reboundBrake
		ax, az, reboundBrake = hold.holdAcceleration(
			wantX,
			wantZ,
			velocity.X,
			velocity.Z,
			rx,
			rz,
			rootVelocity.X,
			rootVelocity.Z,
			distance
		)
		if reboundBrake and not braking then
			reboundBrakes += 1
			localPlayer:SetAttribute(REBOUND_BRAKES_ATTRIBUTE, reboundBrakes)
		end
		braking = reboundBrake
	else
		-- No living character: brake the ball where it is.
		ax, az = hold.acceleration(0, 0, velocity.X, velocity.Z)
		braking = false
	end
	local mass = ball.AssemblyMass
	force.Force = Vector3.new(ax * mass, 0, az * mass)
end

function BallController.Start()
	if started then
		return
	end
	started = true

	localPlayer:SetAttribute(HOLD_RESETS_ATTRIBUTE, holdResets)
	localPlayer:SetAttribute(REBOUND_BRAKES_ATTRIBUTE, reboundBrakes)
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

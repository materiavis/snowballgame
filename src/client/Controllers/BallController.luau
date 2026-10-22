--!strict
-- Pushes the local player's snowball and shows a size / "×N" label above every ball.
-- The server makes this client the ball's network owner, so a locally created VectorForce
-- drives the ball directly; the client never reports sizes or distances to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BallConfig"))

local MULTIPLY_SIGN = "\u{00D7}"

local localPlayer = Players.LocalPlayer

local BallController = {}

local myBall: BasePart? = nil
local pushForce: VectorForce? = nil

local function formatSize(internalSize: number): string
	local cap = BallConfig.VisualCapDiameter
	if internalSize >= cap then
		return string.format("%s%.1f", MULTIPLY_SIGN, internalSize / cap)
	end
	return string.format("%.1f", internalSize)
end

local function createLabel(ball: BasePart, ownerName: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SizeLabel"
	billboard.Adornee = ball
	billboard.Size = UDim2.fromOffset(160, 50)
	-- Extents offset is relative to the ball's size, so the label stays on top as the ball grows.
	billboard.ExtentsOffsetWorldSpace = Vector3.new(0, 1, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard

	local function refresh()
		local size = ball:GetAttribute(BallConfig.SizeAttribute)
		local sizeText = if type(size) == "number" then formatSize(size) else "?"
		label.Text = ownerName .. "\n" .. sizeText
	end
	ball:GetAttributeChangedSignal(BallConfig.SizeAttribute):Connect(refresh)
	refresh()

	billboard.Parent = ball
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
end

local function onBallAdded(child: Instance)
	if not child:IsA("BasePart") then
		return
	end
	local ownerId = child:GetAttribute(BallConfig.OwnerAttribute)
	local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	createLabel(child, if owner then owner.DisplayName else "?")

	if ownerId == localPlayer.UserId then
		attachPushForce(child)
	end
end

local function onBallRemoved(child: Instance)
	if child == myBall then
		myBall = nil
		pushForce = nil
	end
end

-- Returns the force to apply this frame, already scaled by mass.
local function computeForce(ball: BasePart): Vector3
	local mass = ball.AssemblyMass
	local velocity = ball.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if humanoid and root and humanoid.Health > 0 then
		local moveDirection = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
		if moveDirection.Magnitude > 0.1 then
			local direction = moveDirection.Unit
			local radius = ball.Size.X / 2
			local toBall = ball.Position - root.Position
			-- Gap to the surface (not the center), so contact works the same for any ball size.
			local gap = toBall.Magnitude - radius
			local range = BallConfig.ContactRangeBase + radius * BallConfig.ContactRangePerRadius
			local flatToBall = Vector3.new(toBall.X, 0, toBall.Z)
			local facing = if flatToBall.Magnitude > 1e-3 then flatToBall.Unit:Dot(direction) else 1

			if gap <= range and facing >= BallConfig.PushMinFacingDot then
				local along = flatVelocity:Dot(direction)
				local lateral = flatVelocity - direction * along
				local force = -lateral * BallConfig.PushSteerGain
				if along < BallConfig.PushMaxSpeed then
					force += direction * BallConfig.PushAcceleration
				end
				return force * mass
			end
		end
	end

	local speed = flatVelocity.Magnitude
	if speed > BallConfig.BrakeMinSpeed then
		return -flatVelocity.Unit * BallConfig.BrakeAcceleration * mass
	end
	return Vector3.zero
end

function BallController.Start()
	local folder = workspace:WaitForChild(BallConfig.FolderName)
	folder.ChildAdded:Connect(onBallAdded)
	folder.ChildRemoved:Connect(onBallRemoved)
	for _, child in folder:GetChildren() do
		onBallAdded(child)
	end

	RunService.PreSimulation:Connect(function()
		local ball = myBall
		local force = pushForce
		if not ball or not force or not ball.Parent then
			return
		end
		force.Force = computeForce(ball)
	end)
end

return BallController

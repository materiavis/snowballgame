--!strict
-- CameraController (Simulator only, concept 7.3): Roblox's third-person camera, zoomed out
-- automatically the bigger the own ball is, so the whole ball stays in view.
--
-- One render step right after the default camera pushes it out to the exact distance at which
-- the whole ball fits the current view (#95), and at least to the zoom minimum. That also undoes the default "Zoom" occlusion,
-- which pulls the camera in front of the own ball (it has to stay opaque and collidable).
-- Player.CameraMinZoomDistance is lifted only to what the usual view needs (ball ahead, camera
-- level or looking down), so a small ball can be looked at from close up; the max rises with
-- the worst case over every view. Both change on size, field-of-view and viewport changes only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any
local CameraFit = require(script:WaitForChild("CameraFit"))
local HoldMath = require(script.Parent:WaitForChild("BallController"):WaitForChild("HoldMath"))

-- Local player attribute with the zoom minimum this controller set (playtest hook).
local MIN_ZOOM_ATTRIBUTE = "CameraMinZoom"
-- Studio-only playtest hooks (ADR 0002): the distance the current view needs and the worst
-- case over every view, so portrait values can be checked by calculation.
local VIEW_ZOOM_ATTRIBUTE = "CameraViewZoom"
local WORST_ZOOM_ATTRIBUTE = "CameraWorstZoom"
local PUSH_RENDER_STEP = "SnowballCameraPush"
local STUDIO_HOOKS = RunService:IsStudio() and game.PlaceId == 0

local localPlayer = Players.LocalPlayer
local hold = HoldMath.new(BallConfig)

local CameraController = {}

local defaultMinZoom = localPlayer.CameraMinZoomDistance
local defaultMaxZoom = localPlayer.CameraMaxZoomDistance
local myBall: BasePart? = nil
local ballFolder: Instance? = nil
local hasBall = false -- false: the render step does nothing
-- Set in update(), read every frame, so the step computes no angles of its own.
local verticalHalf = 0
local horizontalHalf = 0
local clearance = 0
local minZoomSet = 0 -- the CameraMinZoomDistance update() set; the push never restores less
local shownViewZoom = -1
local ballSizeConnection: RBXScriptConnection? = nil
local cameraConnections: { RBXScriptConnection } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}
local started = false

-- Reused every frame. Real walls still stop the push; balls and characters do not, because
-- players walk through foreign balls and the own ball is exactly what the push looks past.
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater = true

local function refreshWallFilter()
	local excluded: { Instance } = {}
	if ballFolder then
		table.insert(excluded, ballFolder)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	wallParams.FilterDescendantsInstances = excluded
end

local function pushCameraOut()
	local camera = workspace.CurrentCamera
	local ball = myBall
	if not hasBall or not camera or not ball then
		return
	end
	local focus = camera.Focus.Position
	local cameraCFrame = camera.CFrame
	local distance = (cameraCFrame.Position - focus).Magnitude
	local offset = ball.Position - focus
	local look = cameraCFrame.LookVector
	local up = cameraCFrame.UpVector
	local right = cameraCFrame.RightVector
	local viewZoom = CameraFit.viewZoom(
		offset.X,
		offset.Y,
		offset.Z,
		ball.Size.X / 2,
		clearance,
		look.X,
		look.Y,
		look.Z,
		up.X,
		up.Y,
		up.Z,
		right.X,
		right.Y,
		right.Z,
		verticalHalf,
		horizontalHalf
	)
	if STUDIO_HOOKS then
		local shown = math.round(viewZoom * 100) / 100
		if shown ~= shownViewZoom then
			shownViewZoom = shown
			localPlayer:SetAttribute(VIEW_ZOOM_ATTRIBUTE, shown)
		end
	end
	local requiredZoom = CameraFit.pushTarget(viewZoom, minZoomSet)
	if not CameraFit.needsPush(distance, requiredZoom, BallConfig.CameraPushTolerance) then
		return
	end
	local back = -cameraCFrame.LookVector
	local hit = workspace:Raycast(focus, back * requiredZoom, wallParams)
	local wallDistance = if hit then hit.Distance else nil
	local target = CameraFit.pushedDistance(distance, requiredZoom, wallDistance, BallConfig.CameraWallClearance)
	if target > distance then
		camera.CFrame = cameraCFrame + back * (target - distance)
	end
end

local function update()
	local ball = myBall
	local camera = workspace.CurrentCamera
	local worst = 0
	local minimum = 0
	if ball and ball.Parent and camera then
		local viewport = camera.ViewportSize
		local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 1
		local diameter = ball.Size.X
		local holdDistance = hold.holdDistance(diameter)
		verticalHalf, horizontalHalf = CameraFit.halfAngles(camera.FieldOfView, aspect)
		clearance = diameter * BallConfig.CameraFitClearanceShare
		worst = CameraFit.requiredZoom(
			diameter,
			holdDistance,
			camera.FieldOfView,
			aspect,
			BallConfig.CameraFitMargin,
			BallConfig.CameraFocusHeightMin,
			BallConfig.CameraFocusHeightMax
		)
		minimum = CameraFit.minimumZoom(
			diameter,
			holdDistance,
			camera.FieldOfView,
			aspect,
			clearance,
			BallConfig.CameraFocusHeightMin,
			BallConfig.CameraFocusHeightMax,
			BallConfig.CameraMinZoomPitchMinDegrees,
			BallConfig.CameraMinZoomPitchMaxDegrees,
			BallConfig.CameraMinZoomStepDegrees
		)
	end
	hasBall = worst > 0
	local minZoom = math.max(defaultMinZoom, minimum)
	local maxZoom = math.max(defaultMaxZoom, worst + BallConfig.CameraMaxZoomExtra)
	-- Max first, so the minimum is never above the maximum in between.
	localPlayer.CameraMaxZoomDistance = maxZoom
	localPlayer.CameraMinZoomDistance = minZoom
	minZoomSet = minZoom
	localPlayer:SetAttribute(MIN_ZOOM_ATTRIBUTE, math.round(minZoom * 100) / 100)
	if STUDIO_HOOKS then
		localPlayer:SetAttribute(WORST_ZOOM_ATTRIBUTE, math.round(worst * 100) / 100)
	end
end

local function watchCamera()
	for _, connection in cameraConnections do
		connection:Disconnect()
	end
	table.clear(cameraConnections)
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(cameraConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(update))
		table.insert(cameraConnections, camera:GetPropertyChangedSignal("FieldOfView"):Connect(update))
	end
	update()
end

local function setBall(ball: BasePart?)
	if ballSizeConnection then
		ballSizeConnection:Disconnect()
		ballSizeConnection = nil
	end
	myBall = ball
	if ball then
		ballSizeConnection = ball:GetPropertyChangedSignal("Size"):Connect(update)
	end
	update()
end

local function onBallAdded(child: Instance)
	if child:IsA("BasePart") and child:GetAttribute(BallConfig.OwnerAttribute) == localPlayer.UserId then
		setBall(child)
	end
end

local function onBallRemoved(child: Instance)
	if child == myBall then
		setBall(nil)
	end
end

local function onPlayerAdded(player: Player)
	characterConnections[player] = player.CharacterAdded:Connect(refreshWallFilter)
	refreshWallFilter()
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
	refreshWallFilter()
end

function CameraController.Start()
	if started then
		return
	end
	started = true

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	local folder = workspace:WaitForChild(BallConfig.FolderName)
	ballFolder = folder
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	folder.ChildAdded:Connect(onBallAdded)
	folder.ChildRemoved:Connect(onBallRemoved)
	for _, child in folder:GetChildren() do
		onBallAdded(child)
	end

	RunService:BindToRenderStep(PUSH_RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, pushCameraOut)

	print(`[CameraController] started minZoom={localPlayer.CameraMinZoomDistance}`)
end

return CameraController

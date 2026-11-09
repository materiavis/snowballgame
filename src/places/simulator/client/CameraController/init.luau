--!strict
-- CameraController (Simulator only, concept 7.3): Roblox's third-person camera, zoomed out
-- automatically the bigger the own ball is, so the whole ball stays in view.
--
-- It lifts Player.CameraMinZoomDistance (and the max with it) on size, field-of-view and
-- viewport changes; the default camera moves the zoom out when the minimum rises. The default
-- "Zoom" occlusion ignores that minimum and pulls the camera in front of the own ball, which
-- has to stay opaque and collidable, so one render step right after the camera pushes it back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any
local CameraFit = require(script:WaitForChild("CameraFit"))
local HoldMath = require(script.Parent:WaitForChild("BallController"):WaitForChild("HoldMath"))

-- Local player attribute with the zoom minimum this controller set (playtest hook).
local MIN_ZOOM_ATTRIBUTE = "CameraMinZoom"
local PUSH_RENDER_STEP = "SnowballCameraPush"

local localPlayer = Players.LocalPlayer
local hold = HoldMath.new(BallConfig)

local CameraController = {}

local defaultMinZoom = localPlayer.CameraMinZoomDistance
local defaultMaxZoom = localPlayer.CameraMaxZoomDistance
local myBall: BasePart? = nil
local ballFolder: Instance? = nil
local requiredZoom = 0 -- 0 while there is no ball: the render step then does nothing
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
	if requiredZoom <= 0 or not camera then
		return
	end
	local focus = camera.Focus.Position
	local cameraCFrame = camera.CFrame
	local distance = (cameraCFrame.Position - focus).Magnitude
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
	local required = 0
	if ball and ball.Parent and camera then
		local viewport = camera.ViewportSize
		local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 1
		local diameter = ball.Size.X
		required = CameraFit.requiredZoom(
			diameter,
			hold.holdDistance(diameter),
			camera.FieldOfView,
			aspect,
			BallConfig.CameraFitMargin,
			BallConfig.CameraFocusHeightMin,
			BallConfig.CameraFocusHeightMax
		)
	end
	requiredZoom = required
	local minZoom = math.max(defaultMinZoom, required)
	local maxZoom = math.max(defaultMaxZoom, required + BallConfig.CameraMaxZoomExtra)
	-- Max first, so the minimum is never above the maximum in between.
	localPlayer.CameraMaxZoomDistance = maxZoom
	localPlayer.CameraMinZoomDistance = minZoom
	localPlayer:SetAttribute(MIN_ZOOM_ATTRIBUTE, math.round(minZoom * 100) / 100)
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

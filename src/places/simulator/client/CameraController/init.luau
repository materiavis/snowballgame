--!strict
-- CameraController (Simulator only, concept 7.3): Roblox's third-person camera, zoomed out
-- automatically the bigger the own ball is, so the whole ball stays in view.
--
-- It only lifts Player.CameraMinZoomDistance (and the max with it); the default camera module
-- moves the zoom out when the minimum rises. It runs on size, field-of-view and viewport
-- changes, never per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any
local CameraFit = require(script:WaitForChild("CameraFit"))
local HoldMath = require(script.Parent:WaitForChild("BallController"):WaitForChild("HoldMath"))

-- Local player attribute with the zoom minimum this controller set (playtest hook).
local MIN_ZOOM_ATTRIBUTE = "CameraMinZoom"

local localPlayer = Players.LocalPlayer
local hold = HoldMath.new(BallConfig)

local CameraController = {}

local defaultMinZoom = localPlayer.CameraMinZoomDistance
local defaultMaxZoom = localPlayer.CameraMaxZoomDistance
local myBall: BasePart? = nil
local ballSizeConnection: RBXScriptConnection? = nil
local cameraConnections: { RBXScriptConnection } = {}
local started = false

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
			BallConfig.CameraFitMargin
		)
	end
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

function CameraController.Start()
	if started then
		return
	end
	started = true

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	local folder = workspace:WaitForChild(BallConfig.FolderName)
	folder.ChildAdded:Connect(onBallAdded)
	folder.ChildRemoved:Connect(onBallRemoved)
	for _, child in folder:GetChildren() do
		onBallAdded(child)
	end

	print(`[CameraController] started minZoom={localPlayer.CameraMinZoomDistance}`)
end

return CameraController

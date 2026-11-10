--!strict
-- BallGrowthController (Simulator only, concept 7.4, ADR 0002): shows the size the server
-- published and the MAX feedback of the own ball. Only ever reads attributes; this client sends
-- nothing. Everything here is for this one player, so it is built here (ADR 0003 R2) and
-- foreign balls get none of it.
--
-- The top-centre label is deliberately minimal: the HUD (PR #92) replaces it with its own label
-- reading the same `BallSizeMetres` attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ball")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any

local localPlayer = Players.LocalPlayer

local BallGrowthController = {}

local started = false
local myBall: BasePart? = nil
local isMax = false
local sizeLabel: TextLabel
local maxLabel: TextLabel
local glow: PointLight? = nil
local highlight: Highlight? = nil
local arrowHead: ConeHandleAdornment
local arrowShaft: CylinderHandleAdornment
local arrowStep: RBXScriptConnection? = nil

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function refreshLabel()
	local metres = localPlayer:GetAttribute(BallConfig.PlayerSizeMetresAttribute)
	if type(metres) == "number" then
		sizeLabel.Text = NumberFormat.size(metres)
	end
end

local function removeGlow()
	if glow then
		glow:Destroy()
		glow = nil
	end
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

local function showGlow(ball: BasePart)
	removeGlow()
	local color = rgb(BallConfig.MaxGlowColorRGB)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = BallConfig.MaxGlowBrightness
	light.Range = math.clamp(
		ball.Size.X * BallConfig.MaxGlowRangePerDiameter,
		BallConfig.MaxGlowRangeMin,
		BallConfig.MaxGlowRangeMax
	)
	light.Parent = ball
	glow = light

	local outline = Instance.new("Highlight")
	outline.Adornee = ball
	outline.FillColor = color
	outline.OutlineColor = color
	outline.FillTransparency = BallConfig.MaxGlowFillTransparency
	outline.Parent = ball
	highlight = outline
end

-- A horizontal arrow above the ball, pointing at the scale.
local function updateArrow()
	local ball = myBall
	local anchor = localPlayer:GetAttribute(BallConfig.PlayerScaleAnchorAttribute)
	local visible = false
	if ball and ball.Parent and typeof(anchor) == "Vector3" then
		local centre = ball.Position + Vector3.new(0, ball.Size.X / 2 + BallConfig.MaxArrowAboveBall, 0)
		local towards = Vector3.new(anchor.X - centre.X, 0, anchor.Z - centre.Z)
		if towards.Magnitude > 1e-3 then
			local direction = towards.Unit
			-- Handle adornments extend along their +Z axis, CFrame.lookAt looks along -Z.
			local frame = CFrame.lookAt(centre, centre - direction)
			arrowHead.CFrame = frame
			arrowShaft.CFrame = frame * CFrame.new(0, 0, -BallConfig.MaxArrowShaftLength / 2)
			visible = true
		end
	end
	arrowHead.Visible = visible
	arrowShaft.Visible = visible
end

local function stopArrow()
	if arrowStep then
		arrowStep:Disconnect()
		arrowStep = nil
	end
	arrowHead.Visible = false
	arrowShaft.Visible = false
end

local function playSound(ball: BasePart)
	if BallConfig.MaxSoundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = BallConfig.MaxSoundId
	sound.Volume = BallConfig.MaxSoundVolume
	sound.Parent = ball
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
end

local function applyMaxState()
	local ball = myBall
	maxLabel.Visible = isMax
	if isMax and ball then
		showGlow(ball)
		if arrowStep == nil then
			arrowStep = RunService.RenderStepped:Connect(updateArrow)
		end
	else
		removeGlow()
		stopArrow()
	end
end

local function onMaxChanged()
	local nowMax = localPlayer:GetAttribute(BallConfig.PlayerIsMaxAttribute) == true
	if nowMax == isMax then
		return
	end
	isMax = nowMax
	applyMaxState()
	if isMax and myBall then
		playSound(myBall)
	end
end

local function onBallAdded(child: Instance)
	if child:IsA("BasePart") and child:GetAttribute(BallConfig.OwnerAttribute) == localPlayer.UserId then
		myBall = child
		applyMaxState()
	end
end

local function onBallRemoved(child: Instance)
	if child == myBall then
		myBall = nil
		applyMaxState()
	end
end

local function makeLabel(screen: ScreenGui, name: string, height: number, top: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, top)
	label.Size = UDim2.fromOffset(BallConfig.SizeLabelWidth, height)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.Parent = screen
	return label
end

local function buildInterface()
	local screen = Instance.new("ScreenGui")
	screen.Name = "BallGrowthHud"
	screen.ResetOnSpawn = false
	screen.Parent = localPlayer:WaitForChild("PlayerGui")

	local top = BallConfig.SizeLabelTopOffset
	sizeLabel = makeLabel(screen, "SizeLabel", BallConfig.SizeLabelHeight, top, rgb(BallConfig.SizeLabelTextRGB))
	maxLabel = makeLabel(
		screen,
		"MaxLabel",
		BallConfig.MaxLabelHeight,
		top + BallConfig.SizeLabelHeight,
		rgb(BallConfig.MaxLabelTextRGB)
	)
	maxLabel.Text = BallConfig.MaxText
	maxLabel.Visible = false

	-- Handle adornments have no physics and need no asset. The Terrain is their world frame.
	local color = rgb(BallConfig.MaxArrowColorRGB)
	arrowHead = Instance.new("ConeHandleAdornment")
	arrowHead.Name = "MaxArrowHead"
	arrowHead.Adornee = workspace.Terrain
	arrowHead.Height = BallConfig.MaxArrowHeadLength
	arrowHead.Radius = BallConfig.MaxArrowHeadRadius
	arrowHead.Color3 = color
	arrowHead.Visible = false
	arrowHead.Parent = screen

	arrowShaft = Instance.new("CylinderHandleAdornment")
	arrowShaft.Name = "MaxArrowShaft"
	arrowShaft.Adornee = workspace.Terrain
	arrowShaft.Height = BallConfig.MaxArrowShaftLength
	arrowShaft.Radius = BallConfig.MaxArrowShaftRadius
	arrowShaft.Color3 = color
	arrowShaft.Visible = false
	arrowShaft.Parent = screen
end

function BallGrowthController.Start()
	if started then
		return
	end
	started = true

	buildInterface()

	localPlayer:GetAttributeChangedSignal(BallConfig.PlayerSizeMetresAttribute):Connect(refreshLabel)
	localPlayer:GetAttributeChangedSignal(BallConfig.PlayerIsMaxAttribute):Connect(onMaxChanged)
	refreshLabel()

	local folder = workspace:WaitForChild(BallConfig.FolderName)
	folder.ChildAdded:Connect(onBallAdded)
	folder.ChildRemoved:Connect(onBallRemoved)
	for _, child in folder:GetChildren() do
		onBallAdded(child)
	end
	onMaxChanged()

	print(`[BallGrowthController] started ownBall={myBall ~= nil}`)
end

return BallGrowthController

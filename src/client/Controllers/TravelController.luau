--!strict
-- TravelController (all Places, ADR 0010): shows TravelService's short messages ("Teleport
-- fehlgeschlagen. Neuer Versuch …") and gives the Simulator "Lobby" button (#90) one call,
-- TravelController.RequestLobby(). It only shows and requests; the server decides everything.
--
-- The message is deliberately a plain text label (owner decision 2026-11-10); #91 switches it to
-- the popup component.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TravelConfig = require(Shared:WaitForChild("Config"):WaitForChild("Travel")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any

local localPlayer = Players.LocalPlayer

local TravelController = {}

local started = false
local label: TextLabel? = nil
local shownAt = 0

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function buildLabel(): TextLabel
	local screen = Instance.new("ScreenGui")
	screen.Name = "TravelMessage"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = TravelConfig.MessageDisplayOrder
	screen.Parent = localPlayer:WaitForChild("PlayerGui")

	local text = Instance.new("TextLabel")
	text.Name = "Message"
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.new(0.5, 0, 0, TravelConfig.MessageTopOffset)
	text.Size = UDim2.fromOffset(TravelConfig.MessageWidth, TravelConfig.MessageHeight)
	text.BackgroundColor3 = rgb(TravelConfig.MessageBackgroundRGB)
	text.BackgroundTransparency = TravelConfig.MessageBackgroundTransparency
	text.TextColor3 = rgb(TravelConfig.MessageTextRGB)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Text = ""
	text.Visible = false
	text.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, TravelConfig.MessageCornerRadius)
	corner.Parent = text
	local padding = Instance.new("UIPadding")
	local inset = UDim.new(0, TravelConfig.MessagePadding)
	padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom = inset, inset, inset, inset
	padding.Parent = text
	return text
end

local function show(key: any)
	-- Only known keys are shown, so the server never sends free text to the screen.
	local message = if type(key) == "string" then TravelConfig.Messages[key] else nil
	if type(message) ~= "string" then
		return
	end
	local target = label or buildLabel()
	label = target
	target.Text = message
	target.Visible = true
	shownAt = os.clock()
	local mine = shownAt
	task.delay(TravelConfig.MessageSeconds, function()
		-- A newer message keeps the label up for its own full time.
		if shownAt == mine then
			target.Visible = false
		end
	end)
end

function TravelController.Start()
	if started then
		return
	end
	started = true
	local remote = Net.waitForRemote("TravelNotice") :: RemoteEvent
	remote.OnClientEvent:Connect(show)
end

-- For the Simulator "Lobby" button (#90). The server refuses it elsewhere and while a travel is
-- already running, so pressing twice is harmless.
function TravelController.RequestLobby()
	local remote = Net.waitForRemote("TravelRequestLobby") :: RemoteEvent
	remote:FireServer()
end

return TravelController

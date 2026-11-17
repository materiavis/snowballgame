--!strict
-- Lobby portals on the client (concept 7.1, 10.1; ADR 0015). Display only: the server decides
-- who is in which portal, runs the countdown and starts the travel. This controller
--   * puts a board above every portal the server bound (it has a PlayerCount attribute): the
--     mode name, "Coming soon" for a closed portal, and the player count, updated whenever the
--     server rewrites PlayerCount;
--   * shows the countdown ring with the seconds left while the local player's PortalState is
--     Countdown (PortalCountdownEnds is server time), and a short line for Closed, Locked and
--     Travelling.
-- Portals stream in and out (ADR 0009); a board lives under the portal and goes with it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LobbyConfig = require(Config:WaitForChild("Lobby")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any

local Client = script.Parent.Parent
local Theme = require(Client:WaitForChild("Ui"):WaitForChild("Theme"))
local PortalText = require(script:WaitForChild("PortalText"))

local Ui = Theme.Config
local Display = LobbyConfig.Display
local A = LobbyAttributes

local BOARD_NAME = "PortalBoard"

local PortalController = {}

local function colour(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function modeColour(mode: string): Color3
	if LobbyConfig.ClosedPortalModes[mode] then
		return colour(Display.ClosedRGB)
	end
	return colour(if mode == "Singleplayer" then Display.SingleplayerRGB else Display.MultiplayerRGB)
end

local function textLabel(name: string, parent: Instance, order: number, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1 / 3)
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = Theme.Text
	label.TextStrokeTransparency = 0.4
	label.Parent = parent
	return label
end

-- The board of one portal; rebuilt text on every PlayerCount change.
local bindPortal: (portal: Instance) -> ()
function bindPortal(portal: Instance)
	if not portal:IsA("Model") then
		return
	end
	local model = portal :: Model
	local mode = model:GetAttribute(MapConfig.PortalModeAttribute)
	local primary = model.PrimaryPart
	if type(mode) ~= "string" or model:FindFirstChild(BOARD_NAME, true) then
		return
	end
	if primary == nil then
		-- Not expected with Atomic streaming; bind once the PrimaryPart arrives.
		local connection: RBXScriptConnection
		connection = model:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			connection:Disconnect()
			bindPortal(model)
		end)
		return
	end

	local anchor = model:FindFirstChild(MapConfig.LabelAnchorName, true)
	local board = Instance.new("BillboardGui")
	board.Name = BOARD_NAME
	board.Size = UDim2.fromScale(Display.LabelSize[1], Display.LabelSize[2])
	board.MaxDistance = Display.LabelMaxDistance
	board.LightInfluence = 0
	if anchor and (anchor:IsA("Attachment") or anchor:IsA("BasePart")) then
		board.Adornee = anchor
		board.Parent = anchor
	else
		board.StudsOffset = Vector3.new(0, primary.Size.Y / 2 + Display.LabelOffset, 0)
		board.Adornee = primary
		board.Parent = primary
	end
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = board
	local title = textLabel("Title", board, 1, Theme.FontBold)
	title.TextColor3 = modeColour(mode)
	local status = textLabel("Status", board, 2, Theme.FontRegular)
	local players = textLabel("Players", board, 3, Theme.FontRegular)

	local function refresh()
		local count = model:GetAttribute(MapConfig.PlayerCountAttribute)
		-- Only portals the server bound carry PlayerCount; the client never validates a map.
		board.Enabled = count ~= nil
		local label =
			PortalText.label(mode, count, LobbyConfig.ClosedPortalModes[mode] == true, Ui.Text, NumberFormat.number)
		title.Text = label.title
		status.Text = label.status or ""
		status.Visible = label.status ~= nil
		players.Text = label.players
	end
	model:GetAttributeChangedSignal(MapConfig.PlayerCountAttribute):Connect(refresh)
	refresh()
end

local function buildCountdown(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "PortalCountdown"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Ui.DisplayOrder.Hud
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local size = Display.CountdownSize
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, Display.CountdownTopFraction)
	ring.Size = UDim2.fromOffset(size, size)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = Display.CountdownRingThickness
	stroke.Color = colour(Display.SingleplayerRGB)
	stroke.Parent = ring
	local number = Instance.new("TextLabel")
	number.Name = "Seconds"
	number.Size = UDim2.fromScale(1, 1)
	number.BackgroundTransparency = 1
	number.Font = Theme.FontBold
	number.TextScaled = true
	number.TextColor3 = Theme.Text
	number.TextStrokeTransparency = 0.3
	number.Parent = ring

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, Display.CountdownTopFraction)
	status.Size = UDim2.fromOffset(Display.StatusWidth, Display.StatusHeight)
	status.BackgroundColor3 = Theme.Surface
	status.BackgroundTransparency = Ui.PanelTransparency
	status.Font = Theme.FontBold
	status.TextSize = Ui.TextSize.Body
	status.TextColor3 = Theme.Text
	status.TextWrapped = true
	status.Visible = false
	status.Parent = gui
	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(0, Ui.CornerRadius)
	statusCorner.Parent = status

	gui.Parent = playerGui
	return ring, number, stroke, status
end

function PortalController.Start()
	local player = Players.LocalPlayer
	local ring, number, stroke, status = buildCountdown(player:WaitForChild("PlayerGui") :: PlayerGui)

	local function refreshState()
		local state = player:GetAttribute(A.PORTAL_STATE)
		local mode = player:GetAttribute(A.PORTAL_MODE)
		ring.Visible = state == "Countdown"
		if type(mode) == "string" and mode ~= "" then
			stroke.Color = modeColour(mode)
		end
		local line = PortalText.status(state, Ui.Text)
		status.Text = line or ""
		status.Visible = line ~= nil
	end
	player:GetAttributeChangedSignal(A.PORTAL_STATE):Connect(refreshState)
	player:GetAttributeChangedSignal(A.PORTAL_MODE):Connect(refreshState)
	refreshState()

	RunService.RenderStepped:Connect(function()
		if not ring.Visible then
			return
		end
		local endsAt = player:GetAttribute(A.PORTAL_COUNTDOWN_ENDS)
		local now = Workspace:GetServerTimeNow()
		local shown = if type(endsAt) == "number" then PortalText.secondsShown(endsAt, now) else 0
		number.Text = if shown > 0 then tostring(shown) else ""
		-- The ring pulses once per second: thick at each new second, thinning towards the next.
		local fraction = if type(endsAt) == "number" then (endsAt - now) % 1 else 0
		stroke.Thickness = Display.CountdownRingThickness * (0.5 + fraction)
	end)

	CollectionService:GetInstanceAddedSignal(MapConfig.Tags.Portal):Connect(bindPortal)
	for _, portal in CollectionService:GetTagged(MapConfig.Tags.Portal) do
		bindPortal(portal)
	end
end

return PortalController

--!strict
-- The Lobby news board (concept 7.1; ADR 0009, ADR 0015). Puts a SurfaceGui on the Front face of
-- every `NewsBoard` part that streams in: the latest update (Config.Lobby.News.LastUpdate) and a
-- countdown to the next (Workspace attribute LobbyNewsNextUpdateAt, written by the server),
-- updated once a second. Display only.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LobbyConfig = require(Config:WaitForChild("Lobby")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes"))

local Client = script.Parent.Parent
local Theme = require(Client:WaitForChild("Ui"):WaitForChild("Theme"))
local NewsText = require(script:WaitForChild("NewsText"))

local Ui = Theme.Config

local GUI_NAME = "NewsBoardGui"

local NewsBoardController = {}

local boards: { [Instance]: { title: TextLabel, last: TextLabel, next: TextLabel } } = {}

local function label(name: string, parent: Instance, order: number, font: Enum.Font, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.LayoutOrder = order
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, height)
	text.Font = font
	text.TextScaled = true
	text.TextColor3 = Theme.Text
	text.Parent = parent
	return text
end

local function refresh()
	local lines = NewsText.lines(
		Ui.Text,
		LobbyConfig.News.LastUpdate,
		Workspace:GetAttribute(LobbyAttributes.NEWS_NEXT_UPDATE_AT),
		-- Server time, so a wrong device clock does not shift the countdown.
		Workspace:GetServerTimeNow()
	)
	for _, board in boards do
		board.title.Text = lines.title
		board.last.Text = lines.last
		board.next.Text = lines.next
	end
end

local function bind(instance: Instance)
	if not instance:IsA("BasePart") or boards[instance] or instance:FindFirstChild(GUI_NAME) then
		return
	end
	local part = instance :: BasePart
	local gui = Instance.new("SurfaceGui")
	gui.Name = GUI_NAME
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = LobbyConfig.Display.NewsTextSize
	gui.LightInfluence = 0
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.05, 0)
	padding.PaddingBottom = UDim.new(0.05, 0)
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = gui
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	boards[instance] = {
		title = label("Title", gui, 1, Theme.FontBold, 0.4),
		last = label("LastUpdate", gui, 2, Theme.FontRegular, 0.25),
		next = label("NextUpdate", gui, 3, Theme.FontRegular, 0.25),
	}
	gui.Parent = part
	refresh()
end

function NewsBoardController.Start()
	CollectionService:GetInstanceAddedSignal(MapConfig.Tags.NewsBoard):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(MapConfig.Tags.NewsBoard):Connect(function(instance)
		boards[instance] = nil
	end)
	for _, instance in CollectionService:GetTagged(MapConfig.Tags.NewsBoard) do
		bind(instance)
	end
	Workspace:GetAttributeChangedSignal(LobbyAttributes.NEWS_NEXT_UPDATE_AT):Connect(refresh)
	while true do
		task.wait(1)
		if next(boards) ~= nil then
			refresh()
		end
	end
end

return NewsBoardController

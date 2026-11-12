--!strict
-- Simulator HUD (concept 10.2, issue #35 Prototyp slice, ADR 0008): Coins top left, ball size
-- top centre, menu buttons down the left edge (only Upgrades for now) and the load hint.
-- Display only. Coins, DataLoadStatus, BallSizeMetres and BallIsMax are player attributes
-- written by the server on every server (CurrencyService, DataService, BallService); this
-- controller reads them and never decides a value.
-- The Upgrades window content is UpgradesPanel (#36, ADR 0010). It opens with U, the left-edge
-- button, D-pad right and an upgrade stand's prompt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local BallSize = require(UiFolder:WaitForChild("BallSize"))
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local LoadStatus = require(UiFolder:WaitForChild("LoadStatus"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local MenuController = require(Client:WaitForChild("Controllers"):WaitForChild("MenuController"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ball")) :: any
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any
local UpgradesPanel = require(script:WaitForChild("UpgradesPanel"))

local Ui = Theme.Config

local UPGRADES_WINDOW = "Upgrades"
local COINS_ATTRIBUTE = "Coins"
local STATUS_ATTRIBUTE = "DataLoadStatus"

local SimulatorHudController = {}

type ValuePanel = { frame: Frame, caption: TextLabel, value: TextLabel }

-- A panel with a small caption over a value, e.g. "Coins" over "1.2K".
local function valuePanel(name: string, caption: string): ValuePanel
	local z = Ui.ZIndex.Hud
	local frame = Components.panel(name, z)
	local captionLabel = Components.label("Caption", caption, Ui.TextSize.Caption, z + 1, { muted = true })
	captionLabel.Parent = frame
	local valueLabel = Components.label("Value", Ui.Text.Missing, Ui.TextSize.Value, z + 1, {
		bold = true,
		autoLocalize = false,
	})
	valueLabel.Parent = frame
	return { frame = frame, caption = captionLabel, value = valueLabel }
end

local function layoutValuePanel(panel: ValuePanel, r: Layout.Rect, padding: number)
	Components.place(panel.frame, r)
	local inner = r.height - 2 * padding
	local captionH = math.floor(inner * Ui.Hud.CaptionFraction)
	Components.place(panel.caption, { x = padding, y = padding, width = r.width - 2 * padding, height = captionH })
	Components.place(panel.value, {
		x = padding,
		y = padding + captionH,
		width = r.width - 2 * padding,
		height = inner - captionH,
	})
end

function SimulatorHudController.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SimulatorHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Ui.DisplayOrder.Hud

	local coins = valuePanel("Coins", Ui.Text.Coins)
	coins.frame.Parent = gui
	local ballSize = valuePanel("BallSize", Ui.Text.BallSize)
	ballSize.frame.Parent = gui

	local hint = Components.label("LoadHint", "", Ui.TextSize.Hint, Ui.ZIndex.Hud + 1, { bold = true })
	hint.BackgroundColor3 = Theme.Brand
	hint.BackgroundTransparency = 0
	hint.Visible = false
	hint.Parent = gui

	local upgradesButton = Components.button("UpgradesButton", Ui.Text.Upgrades, Ui.ZIndex.Hud + 1)
	upgradesButton.Parent = gui
	local menuButtons = { upgradesButton }

	local window = Components.window("UpgradesWindow", Ui.Text.Upgrades)
	local upgrades = UpgradesPanel.build(window.content)
	window.root.Parent = gui

	local function relayout()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local screen = { width = size.X, height = size.Y, touch = UserInputService.TouchEnabled }
		local hud = Layout.hud(screen, Ui, #menuButtons)
		local padding = Layout.px(Ui.Window.Padding, hud.scale) // 2
		layoutValuePanel(coins, hud.coins, padding)
		layoutValuePanel(ballSize, hud.ballSize, padding)
		Components.place(hint, hud.hint)
		for index, button in menuButtons do
			Components.place(button, hud.menuButtons[index])
		end
		Components.scaleText(gui, hud.scale)
		local windowLayout = Layout.window(screen, Ui)
		Components.applyWindow(window, windowLayout, hud.scale)
		-- Same content width as Components.applyWindow.
		upgrades.layout(math.max(0, windowLayout.rect.width - 2 * windowLayout.padding), hud.button, hud.scale)
	end

	local function refreshBalances()
		local status = player:GetAttribute(STATUS_ATTRIBUTE)
		coins.value.Text = LoadStatus.balanceText(status, player:GetAttribute(COINS_ATTRIBUTE), NumberFormat.number, Ui)
		local hintText = LoadStatus.hint(status, Ui)
		hint.Text = hintText or ""
		hint.Visible = hintText ~= nil
	end

	local function refreshBallSize()
		ballSize.value.Text =
			BallSize.valueText(player:GetAttribute(BallConfig.PlayerSizeMetresAttribute), NumberFormat.size, Ui)
		local caption, isMax = BallSize.caption(player:GetAttribute(BallConfig.PlayerIsMaxAttribute), Ui)
		ballSize.caption.Text = caption
		ballSize.caption.TextColor3 = if isMax then Theme.Max else Theme.TextMuted
	end

	MenuController.register({
		id = UPGRADES_WINDOW,
		root = window.root,
		selection = window.close,
		toggleKeys = Ui.Keybinds.Upgrades.Toggle,
		openKeys = Ui.Keybinds.Upgrades.Open,
		setOpen = function(open: boolean)
			window.root.Visible = open
		end,
	})
	upgradesButton.Activated:Connect(function()
		MenuController.toggle(UPGRADES_WINDOW)
	end)
	window.close.Activated:Connect(function()
		MenuController.close(UPGRADES_WINDOW)
	end)
	-- An upgrade stand opens the same window as U (ADR 0009). The server owns the prompt; it
	-- changes nothing by itself.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if CollectionService:HasTag(prompt, MapConfig.UpgradeStand.PromptTag) then
			MenuController.open(UPGRADES_WINDOW)
		end
	end)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	player:GetAttributeChangedSignal(COINS_ATTRIBUTE):Connect(refreshBalances)
	player:GetAttributeChangedSignal(STATUS_ATTRIBUTE):Connect(refreshBalances)
	player:GetAttributeChangedSignal(BallConfig.PlayerSizeMetresAttribute):Connect(refreshBallSize)
	player:GetAttributeChangedSignal(BallConfig.PlayerIsMaxAttribute):Connect(refreshBallSize)

	refreshBalances()
	refreshBallSize()
	gui.Parent = playerGui
	relayout()
end

return SimulatorHudController

--!strict
-- Simulator HUD (concept 10.2, issues #35 and #90, ADR 0008): Coins top left, ball size top
-- centre with the progress bar to the zone maximum and the zone name under it, menu buttons
-- down the left edge, the load hint and the centre pop-up.
-- Display only. Coins, DataLoadStatus, BallSizeMetres, BallIsMax and BallZone are player
-- attributes written by the server on every server (CurrencyService, DataService, BallService);
-- this controller reads them and never decides a value. The zone maximum comes from the shared
-- zone formula for the published zone.
-- Left-edge buttons are drawn for what MenuController.registerButton holds: Upgrades here,
-- Pets (#41), Zonen-Teleport (#39) and Lobby (Travel follow-up) once their features register.
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
local ZoneProgress = require(UiFolder:WaitForChild("ZoneProgress"))
local Controllers = Client:WaitForChild("Controllers")
local MenuController = require(Controllers:WaitForChild("MenuController"))
local PopupController = require(Controllers:WaitForChild("PopupController"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ball")) :: any
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("Map")) :: any
local ZonesConfig = require(Shared:WaitForChild("Config"):WaitForChild("Zones")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any
local TestButtons = require(script:WaitForChild("TestButtons"))
local UpgradesPanel = require(script:WaitForChild("UpgradesPanel"))

local Ui = Theme.Config

local UPGRADES_WINDOW = "Upgrades"
local COINS_ATTRIBUTE = "Coins"
local STATUS_ATTRIBUTE = "DataLoadStatus"

local SimulatorHudController = {}

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

	local coins = Components.valuePanel("Coins", Ui.Text.Coins)
	coins.frame.Parent = gui
	local ballSize = Components.valuePanel("BallSize", Ui.Text.BallSize)
	ballSize.frame.Parent = gui

	local progress = Components.progressBar("ZoneProgress")
	progress.frame.Parent = gui
	local zoneName = Components.label("ZoneName", Ui.Text.ZoneNamePlaceholder, Ui.TextSize.Caption, Ui.ZIndex.Hud + 1, {
		bold = true,
	})
	-- A backing so the name stays readable over snow.
	zoneName.BackgroundColor3 = Theme.Surface
	zoneName.BackgroundTransparency = Ui.PanelTransparency
	zoneName.Parent = gui

	local hint = Components.label("LoadHint", "", Ui.TextSize.Hint, Ui.ZIndex.Hud + 1, { bold = true })
	hint.BackgroundColor3 = Theme.Brand
	hint.BackgroundTransparency = 0
	hint.Visible = false
	hint.Parent = gui

	-- One button per Config.Ui.LeftButtons id, hidden until MenuController holds a registration
	-- for it. Named "<id>Button" (UpgradesButton, PetsButton, ZoneTeleportButton, LobbyButton).
	local menuButtons: { [string]: TextButton } = {}
	for _, id in Ui.LeftButtons do
		local button = Components.button(`{id}Button`, Ui.Text[id], Ui.ZIndex.Hud + 1)
		button.Visible = false
		button.Activated:Connect(function()
			MenuController.activateButton(id)
		end)
		button.Parent = gui
		menuButtons[id] = button
	end

	local window = Components.window("UpgradesWindow", Ui.Text.Upgrades)
	local upgrades = UpgradesPanel.build(window.content)
	window.root.Parent = gui

	PopupController.attach(gui)

	local function relayout()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local screen = { width = size.X, height = size.Y, touch = UserInputService.TouchEnabled }
		local visible = MenuController.visibleButtons()
		local hud = Layout.hud(screen, Ui, #visible)
		local padding = Layout.px(Ui.Window.Padding, hud.scale) // 2
		Components.placeValuePanel(coins, hud.coins, padding)
		Components.placeValuePanel(ballSize, hud.ballSize, padding)
		Components.place(progress.frame, hud.progress)
		Components.place(zoneName, hud.zoneName)
		Components.place(hint, hud.hint)
		local avoid = { hud.coins, hud.ballSize, hud.progress, hud.zoneName, hud.hint }
		for _, button in menuButtons do
			button.Visible = false
		end
		for index, id in visible do
			local button = menuButtons[id]
			Components.place(button, hud.menuButtons[index])
			button.Visible = true
			table.insert(avoid, hud.menuButtons[index])
		end
		Components.scaleText(gui, hud.scale)
		PopupController.place(Layout.popup(screen, Ui, avoid).rect, hud.scale)
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
		local metres = player:GetAttribute(BallConfig.PlayerSizeMetresAttribute)
		local zone = player:GetAttribute(BallConfig.PlayerZoneAttribute)
		ballSize.value.Text = BallSize.valueText(metres, NumberFormat.size, Ui)
		local caption, isMax = BallSize.caption(player:GetAttribute(BallConfig.PlayerIsMaxAttribute), Ui)
		ballSize.caption.Text = caption
		ballSize.caption.TextColor3 = if isMax then Theme.Max else Theme.TextMuted
		Components.setProgress(
			progress,
			ZoneProgress.fraction(metres, zone, Formulas.Zones),
			ZoneProgress.barText(metres, zone, Formulas.Zones, NumberFormat.size, Ui)
		)
		zoneName.Text = ZoneProgress.zoneName(zone, ZonesConfig.Names, Formulas.Zones, Ui)
	end

	MenuController.register({
		id = UPGRADES_WINDOW,
		root = window.root,
		selection = window.close,
		setOpen = function(open: boolean)
			window.root.Visible = open
		end,
	})
	-- U, D-pad right and the button come from the left-edge registry (Config.Ui.Keybinds.Upgrades).
	MenuController.registerButton({ id = UPGRADES_WINDOW, window = UPGRADES_WINDOW })
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
	MenuController.onButtonsChanged(relayout)
	player:GetAttributeChangedSignal(COINS_ATTRIBUTE):Connect(refreshBalances)
	player:GetAttributeChangedSignal(STATUS_ATTRIBUTE):Connect(refreshBalances)
	for _, name in
		{ BallConfig.PlayerSizeMetresAttribute, BallConfig.PlayerIsMaxAttribute, BallConfig.PlayerZoneAttribute }
	do
		player:GetAttributeChangedSignal(name):Connect(refreshBallSize)
	end

	refreshBalances()
	refreshBallSize()
	gui.Parent = playerGui
	relayout()
	TestButtons.start(player)
end

return SimulatorHudController

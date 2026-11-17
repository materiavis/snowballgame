--!strict
-- Lobby HUD (concept 10.2 and 6.5, #90, ADR 0008): Coins and Snow Coins top left, the load hint
-- top centre and the centre pop-up. No left-edge buttons yet (Shop, Handel, Einstellungen: #91).
-- Display only, with the same rules as the Simulator: balances only while DataLoadStatus is
-- "Loaded", otherwise "–"; the hint only on "Failed" (Config.Ui.LoadHints). Coins, SnowCoins and
-- DataLoadStatus are player attributes written by the server on every server.
-- The ScreenGui has ResetOnSpawn off and this controller lives in PlayerScripts, so the HUD
-- survives the respawns of the Lobby (no floor yet, the character falls and respawns).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local LoadStatus = require(UiFolder:WaitForChild("LoadStatus"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local PopupController = require(Client:WaitForChild("Controllers"):WaitForChild("PopupController"))
local NumberFormat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NumberFormat")) :: any

local Ui = Theme.Config

local STATUS_ATTRIBUTE = "DataLoadStatus"
-- Currency ids of Config.Currency, which are also the balance attribute names (ADR 0007).
local COINS_ATTRIBUTE = "Coins"
local SNOW_COINS_ATTRIBUTE = "SnowCoins"

local LobbyHudController = {}

function LobbyHudController.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Ui.DisplayOrder.Hud

	local coins = Components.valuePanel("Coins", Ui.Text.Coins)
	coins.frame.Parent = gui
	local snowCoins = Components.valuePanel("SnowCoins", Ui.Text.SnowCoins)
	snowCoins.frame.Parent = gui

	local hint = Components.label("LoadHint", "", Ui.TextSize.Hint, Ui.ZIndex.Hud + 1, { bold = true })
	hint.BackgroundColor3 = Theme.Brand
	hint.BackgroundTransparency = 0
	hint.Visible = false
	hint.Parent = gui

	PopupController.attach(gui)

	local function relayout()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local screen = { width = size.X, height = size.Y, touch = UserInputService.TouchEnabled }
		local hud = Layout.lobbyHud(screen, Ui)
		local padding = Layout.px(Ui.Window.Padding, hud.scale) // 2
		Components.placeValuePanel(coins, hud.coins, padding)
		Components.placeValuePanel(snowCoins, hud.snowCoins, padding)
		Components.place(hint, hud.hint)
		Components.scaleText(gui, hud.scale)
		PopupController.place(Layout.popup(screen, Ui, { hud.coins, hud.snowCoins, hud.hint }).rect, hud.scale)
	end

	local function refresh()
		local status = player:GetAttribute(STATUS_ATTRIBUTE)
		coins.value.Text = LoadStatus.balanceText(status, player:GetAttribute(COINS_ATTRIBUTE), NumberFormat.number, Ui)
		snowCoins.value.Text =
			LoadStatus.balanceText(status, player:GetAttribute(SNOW_COINS_ATTRIBUTE), NumberFormat.number, Ui)
		local hintText = LoadStatus.hint(status, Ui)
		hint.Text = hintText or ""
		hint.Visible = hintText ~= nil
	end

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	for _, name in { STATUS_ATTRIBUTE, COINS_ATTRIBUTE, SNOW_COINS_ATTRIBUTE } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end

	refresh()
	gui.Parent = playerGui
	relayout()
end

return LobbyHudController

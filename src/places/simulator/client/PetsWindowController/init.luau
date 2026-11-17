--!strict
-- Pets window (concept 7.9, 10.2, ADR 0008, ADR 0013): the inventory grid with equip and unequip,
-- slots used/total and the pet multiplier. Opens with P, D-pad left and the left-edge "Pets"
-- button (MenuController.registerButton, Config.Ui.Keybinds.Pets); closes with X, P or B.
--
-- The window lives in its own ScreenGui "PetsHud" above the HUD and takes its size and place from
-- Layout.window, like the Upgrades window. Simulator only in the Vertical Slice; the Lobby window
-- is #103.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local MenuController = require(Client:WaitForChild("Controllers"):WaitForChild("MenuController"))
local PetsPanel = require(script:WaitForChild("PetsPanel"))

local Ui = Theme.Config

local WINDOW = "Pets"

local PetsWindowController = {}

function PetsWindowController.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "PetsHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Ui.DisplayOrder.PetsHud

	local window = Components.window("PetsWindow", Ui.Text.Pets)
	local panel = PetsPanel.build(window.content)
	window.root.Parent = gui

	local function relayout()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local screen = { width = size.X, height = size.Y, touch = UserInputService.TouchEnabled }
		local scale = Layout.scale(screen, Ui)
		local windowLayout = Layout.window(screen, Ui)
		Components.applyWindow(window, windowLayout, scale)
		-- Same content size as Components.applyWindow.
		local p = windowLayout.padding
		panel.layout(
			math.max(0, windowLayout.rect.width - 2 * p),
			math.max(0, windowLayout.rect.height - windowLayout.titleHeight - 2 * p),
			Layout.button(screen, Ui),
			scale
		)
	end

	MenuController.register({
		id = WINDOW,
		root = window.root,
		selection = window.close,
		setOpen = function(open: boolean)
			window.root.Visible = open
		end,
	})
	MenuController.registerButton({ id = WINDOW, window = WINDOW })
	window.close.Activated:Connect(function()
		MenuController.close(WINDOW)
	end)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	gui.Parent = playerGui
	relayout()
end

return PetsWindowController

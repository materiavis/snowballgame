--!strict
-- ZoneController (Simulator only, #39, concept 7.6, ADR 0014): the barrier unlock window, the
-- zone teleport window with its left-edge button (T, D-pad up) and the barriers on this client
-- (labels, prompts, local passability, walking in). Display and requests only: the unlocked
-- zones, coins and barrier states are server-written attributes, and every request (ZoneRequests)
-- carries only a zone number that ZoneService checks again.
--
-- The windows live in their own ScreenGui PlayerGui.ZoneHud and use the window stack, layout
-- and components of ADR 0008, so the ⅔ limit, the clear zones and X / key / B closing apply.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local Controllers = Client:WaitForChild("Controllers")
local MenuController = require(Controllers:WaitForChild("MenuController"))
local PopupController = require(Controllers:WaitForChild("PopupController"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DisplayConfig = require(Shared:WaitForChild("Config"):WaitForChild("Display")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any
local PopupAmount = require(Shared:WaitForChild("PopupAmount"))
local Barriers = require(script:WaitForChild("Barriers"))
local TeleportWindow = require(script:WaitForChild("TeleportWindow"))
local UnlockWindow = require(script:WaitForChild("UnlockWindow"))

local Ui = Theme.Config

local UNLOCK_WINDOW = "ZoneUnlock"
local TELEPORT_WINDOW = "ZoneTeleport"
local TELEPORT_BUTTON = "ZoneTeleport"

local ZoneController = {}

function ZoneController.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local missingUp = PopupAmount.new(DisplayConfig)

	local gui = Instance.new("ScreenGui")
	gui.Name = "ZoneHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Ui.DisplayOrder.Hud

	local unlock = UnlockWindow.build(function()
		MenuController.close(UNLOCK_WINDOW)
	end)
	unlock.window.root.Parent = gui
	local teleport = TeleportWindow.build(function()
		MenuController.close(TELEPORT_WINDOW)
	end)
	teleport.window.root.Parent = gui

	local function relayout()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local screen = { width = size.X, height = size.Y, touch = UserInputService.TouchEnabled }
		local scale = Layout.scale(screen, Ui)
		local button = Layout.button(screen, Ui)
		local windowLayout = Layout.window(screen, Ui)
		-- Same content box as Components.applyWindow.
		local contentWidth = math.max(0, windowLayout.rect.width - 2 * windowLayout.padding)
		local contentHeight =
			math.max(0, windowLayout.rect.height - windowLayout.titleHeight - 2 * windowLayout.padding)
		Components.applyWindow(unlock.window, windowLayout, scale)
		unlock.layout(contentWidth, button, scale)
		Components.applyWindow(teleport.window, windowLayout, scale)
		teleport.layout(contentWidth, contentHeight, button, scale)
	end

	MenuController.register({
		id = UNLOCK_WINDOW,
		root = unlock.window.root,
		selection = unlock.window.close,
		setOpen = function(open: boolean)
			unlock.window.root.Visible = open
		end,
	})
	MenuController.register({
		id = TELEPORT_WINDOW,
		root = teleport.window.root,
		selection = teleport.window.close,
		setOpen = function(open: boolean)
			if open then
				teleport.refresh()
			end
			teleport.window.root.Visible = open
		end,
	})
	-- T, D-pad up and the left-edge button come from the registry (Config.Ui.Keybinds.ZoneTeleport).
	MenuController.registerButton({ id = TELEPORT_BUTTON, window = TELEPORT_WINDOW })

	Barriers.start({
		openWindow = function(zone: number, price: number)
			unlock.prepare(zone, NumberFormat.price(price))
			MenuController.open(UNLOCK_WINDOW)
		end,
		showMissing = function(missing: number)
			PopupController.show("BarrierNeedMore", { missingUp(missing) })
		end,
	})

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	gui.Parent = playerGui
	relayout()
end

return ZoneController

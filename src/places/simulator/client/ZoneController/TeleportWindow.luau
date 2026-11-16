--!strict
-- The zone teleport window (#39, concept 7.6 "Zonen-Teleport (T)": a list of all unlocked
-- zones). Opens with T, D-pad up and the left-edge "Teleport" button (MenuController). One row
-- per unlocked zone of this world, from the server's ZonesUnlocked attribute (ZoneView); a tap
-- sends only the zone number and closes the window. The server checks the unlock, the zone
-- start and the wait after the last teleport.
--
-- Playtest handles: PlayerGui.ZoneHud.ZoneTeleportWindow.Content.Rows with one TextButton
-- Zone<N> per row (attribute Zone), and Content.Empty ("–") while nothing can be listed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneUi = require(Shared:WaitForChild("Config"):WaitForChild("ZoneUi")) :: any
local ZonesConfig = require(Shared:WaitForChild("Config"):WaitForChild("Zones")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))
local ZoneAttributes = require(Shared:WaitForChild("ZoneAttributes"))
local ZoneRequests = require(script.Parent:WaitForChild("ZoneRequests"))
local ZoneView = require(script.Parent:WaitForChild("ZoneView"))

export type TeleportWindow = {
	window: Components.Window,
	refresh: () -> (),
	layout: (contentWidth: number, contentHeight: number, button: number, scale: number) -> (),
}

local Ui = Theme.Config
local config = ZoneUi.TeleportWindow
local STATUS_ATTRIBUTE = "DataLoadStatus"

local TeleportWindow = {}

function TeleportWindow.build(close: () -> ()): TeleportWindow
	local player = Players.LocalPlayer
	local window = Components.window("ZoneTeleportWindow", Ui.Text.ZoneTeleportTitle)
	local z = Ui.ZIndex.Window + 2

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ZIndex = z
	list.CanvasSize = UDim2.new()
	list.Parent = window.content

	local empty = Components.label("Empty", Ui.Text.Missing, Ui.TextSize.Body, z, { autoLocalize = false })
	empty.Parent = window.content

	window.close.Activated:Connect(close)

	local buttons: { TextButton } = {}
	local sizes = { width = 0, button = 0, gap = 0, scale = 1 }

	local function place()
		local y = 0
		for _, button in buttons do
			Components.place(button, { x = 0, y = y, width = sizes.width, height = sizes.button })
			y += sizes.button + sizes.gap
		end
		list.CanvasSize = UDim2.fromOffset(0, math.max(0, y - sizes.gap))
		Components.scaleText(list, sizes.scale)
	end

	local function refresh()
		for _, button in buttons do
			button:Destroy()
		end
		table.clear(buttons)
		local rows = ZoneView.teleportRows(
			player:GetAttribute(STATUS_ATTRIBUTE),
			player:GetAttribute(ZoneAttributes.UNLOCKED),
			function(value: any)
				return ZoneAttributes.decode(value, Formulas.Zones.isZone)
			end,
			Formulas.Zones.worldOf,
			PlaceInfo.WorldIndex :: number,
			ZonesConfig.Names,
			Ui.Text
		)
		empty.Visible = rows == nil or #rows == 0
		list.Visible = not empty.Visible
		for _, row in rows or {} do
			local button = Components.button(`Zone{row.zone}`, row.text, z + 1)
			button.AutoLocalize = false -- carries a zone number
			button:SetAttribute("Zone", row.zone)
			button.Activated:Connect(function()
				close()
				ZoneRequests.teleport(row.zone)
			end)
			button.Parent = list
			table.insert(buttons, button)
		end
		place()
	end

	local function layout(contentWidth: number, contentHeight: number, button: number, scale: number)
		local bar = Layout.px(config.ScrollBarThickness, scale)
		list.ScrollBarThickness = bar
		Components.place(list, { x = 0, y = 0, width = contentWidth, height = contentHeight })
		Components.place(empty, { x = 0, y = 0, width = contentWidth, height = button })
		sizes.width = math.max(0, contentWidth - bar - Layout.px(config.Gap, scale))
		sizes.button = button
		sizes.gap = Layout.px(config.Gap, scale)
		sizes.scale = scale
		place()
	end

	player:GetAttributeChangedSignal(ZoneAttributes.UNLOCKED):Connect(refresh)
	player:GetAttributeChangedSignal(STATUS_ATTRIBUTE):Connect(refresh)
	refresh()

	return { window = window, refresh = refresh, layout = layout }
end

return table.freeze(TeleportWindow)

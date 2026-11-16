--!strict
-- The "first sale" hint (concept 10.1, ADR 0017): a pulsing ring and an arrow at the HUD's
-- Upgrades button and, beside the arrow, the key of the last used device (U, D-pad right, or a
-- tapping finger on touch). The HUD is not changed: the button is found by name
-- (PlayerGui.SimulatorHud.UpgradesButton, ADR 0008) and the hint is drawn in the separate,
-- inert TutorialHints layer with the same insets. Hidden while the Upgrades window is open.

local Layout = require(script.Parent.Parent.Parent:WaitForChild("Ui"):WaitForChild("Layout"))
local TutorialGlyphs = require(script.Parent.Parent.Parent:WaitForChild("Ui"):WaitForChild("TutorialGlyphs"))
local TutorialHand = require(script.Parent.Parent.Parent:WaitForChild("Ui"):WaitForChild("TutorialHand"))

local HUD_NAME = "SimulatorHud"
local BUTTON_NAME = "UpgradesButton"

export type Options = {
	gui: ScreenGui,
	ui: any, -- Config.Ui
	tutorial: any, -- Config.Tutorial
	hud: Instance, -- PlayerGui
	getDevice: () -> string,
	onDeviceChanged: (fn: (device: string) -> ()) -> () -> (),
}

export type Hint = {
	setActive: (active: boolean) -> (),
	setWindowOpen: (open: boolean) -> (),
	isShown: () -> boolean,
}

local UpgradesHint = {}

function UpgradesHint.new(options: Options): Hint
	local gui = options.gui
	local display = options.tutorial.Display
	local active, windowOpen = false, false
	local parts: { TutorialHand.Handle } = {}
	local watched: GuiObject? = nil
	local connections: { RBXScriptConnection } = {}

	local function clear()
		for _, part in parts do
			part.destroy()
		end
		table.clear(parts)
	end

	local function button(): GuiObject?
		local hud = options.hud:FindFirstChild(HUD_NAME)
		local found = hud and hud:FindFirstChild(BUTTON_NAME)
		return if found and found:IsA("GuiObject") then found else nil
	end

	local render: () -> ()

	local function watch(target: GuiObject?)
		if target == watched then
			return
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		watched = target
		if target then
			for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do
				table.insert(connections, target:GetPropertyChangedSignal(property):Connect(render))
			end
		end
	end

	render = function()
		clear()
		local target = button()
		watch(target)
		local menuGlyph = ""
		if active and not windowOpen and target and target.Visible and target.AbsoluteSize.X > 0 then
			local offset = target.AbsolutePosition - gui.AbsolutePosition
			local r = { x = offset.X, y = offset.Y, width = target.AbsoluteSize.X, height = target.AbsoluteSize.Y }
			local size = gui.AbsoluteSize
			local scale = Layout.scale({ width = size.X, height = size.Y, touch = false }, options.ui)
			table.insert(parts, TutorialHand.pointAt(gui, r, scale, display))
			local glyph = TutorialGlyphs.menuKey(options.getDevice() :: any, options.ui.Keybinds.Upgrades)
			local key = math.floor(display.KeySize * scale + 0.5)
			local gap = math.floor(display.PointerGap * scale + 0.5)
			local arm = math.floor(display.PointerArmLength * scale + 0.5)
			local x = r.x + r.width + 3 * gap + arm + key / 2
			table.insert(parts, TutorialHand.menuKey(gui, glyph, x, r.y + r.height / 2, scale, display))
			menuGlyph = TutorialGlyphs.describe(glyph)
		end
		gui:SetAttribute("TutorialMenuGlyph", menuGlyph)
	end

	options.onDeviceChanged(function()
		render()
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(render)
	options.hud.DescendantAdded:Connect(function(child)
		if child.Name == BUTTON_NAME and active then
			render()
		end
	end)

	return {
		setActive = function(value: boolean)
			if value ~= active then
				active = value
				render()
			end
		end,
		setWindowOpen = function(value: boolean)
			if value ~= windowOpen then
				windowOpen = value
				render()
			end
		end,
		isShown = function(): boolean
			return #parts > 0
		end,
	}
end

return table.freeze(UpgradesHint)

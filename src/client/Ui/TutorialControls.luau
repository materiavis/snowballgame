--!strict
-- The "how to move" hint shared by the Lobby (LobbyMove) and the Simulator (ZoneMove): an
-- animated finger on the symbol of the last used device (W A S D, the touch joystick or the
-- gamepad stick; concept 3.2, 10.1; ADR 0017). Redrawn when the device changes or the screen is
-- resized. Writes `TutorialGlyph` and `TutorialDevice` on the hint ScreenGui for the playtest.

local UserInputService = game:GetService("UserInputService")

local Layout = require(script.Parent:WaitForChild("Layout"))
local TutorialGlyphs = require(script.Parent:WaitForChild("TutorialGlyphs"))
local TutorialHand = require(script.Parent:WaitForChild("TutorialHand"))

export type Options = {
	gui: ScreenGui,
	ui: any, -- Config.Ui
	tutorial: any, -- Config.Tutorial
	getDevice: () -> string,
	onDeviceChanged: (fn: (device: string) -> ()) -> () -> (),
}

export type Controls = { setVisible: (visible: boolean) -> (), destroy: () -> () }

local TutorialControls = {}

function TutorialControls.new(options: Options): Controls
	local gui = options.gui
	local display = options.tutorial.Display
	local visible = false
	local current: TutorialHand.Handle? = nil

	local function clear()
		if current then
			current.destroy()
			current = nil
		end
	end

	local function render()
		clear()
		local device = options.getDevice()
		gui:SetAttribute("TutorialDevice", device)
		if not visible then
			gui:SetAttribute("TutorialGlyph", "")
			return
		end
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local screen = { width = size.X, height = size.Y, touch = UserInputService.TouchEnabled or device == "Touch" }
		local scale = Layout.scale(screen, options.ui)
		local glyph = TutorialGlyphs.controls(device :: any, options.tutorial.Glyphs)
		local zones = Layout.zones(screen, options.ui)
		local rect = TutorialGlyphs.controlsRect(glyph, screen, zones.joystick, scale, display)
		current = TutorialHand.controls(gui, glyph, rect, scale, display)
		gui:SetAttribute("TutorialGlyph", TutorialGlyphs.describe(glyph))
	end

	local disconnectDevice = options.onDeviceChanged(function()
		render()
	end)
	local resized = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(render)

	return {
		setVisible = function(value: boolean)
			if value ~= visible then
				visible = value
				render()
			end
		end,
		destroy = function()
			disconnectDevice()
			resized:Disconnect()
			clear()
		end,
	}
end

return table.freeze(TutorialControls)

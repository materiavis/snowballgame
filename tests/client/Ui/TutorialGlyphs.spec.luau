--!strict
-- The symbol of the last used device (concept 3.2, 10.1; #42 ADR 0017) and where the controls
-- symbol goes. Pure, checked with the real Config.Ui and Config.Tutorial.

local T = require("../../TestKit")
local Layout = require("../../../src/client/Ui/Layout")
local TutorialGlyphs = require("../../../src/client/Ui/TutorialGlyphs")
local Tutorial = require("../../../src/shared/Config/Tutorial")
local Ui = require("../../../src/shared/Config/Ui")

local SCREENS = {
	{ name = "iPhone SE landscape", width = 667, height = 375, touch = true },
	{ name = "small landscape phone", width = 568, height = 262, touch = true },
	{ name = "portrait phone", width = 375, height = 667, touch = true },
	{ name = "tablet", width = 1024, height = 744, touch = true },
	{ name = "desktop", width = 1920, height = 1080, touch = false },
	{ name = "small desktop", width = 1024, height = 600, touch = false },
}

local function inside(inner: any, outer: any): boolean
	return inner.x >= outer.x - 1e-6
		and inner.y >= outer.y - 1e-6
		and inner.x + inner.width <= outer.x + outer.width + 1e-6
		and inner.y + inner.height <= outer.y + outer.height + 1e-6
end

return T.suite("TutorialGlyphs", function(test)
	test("controls: W A S D on keyboard, the joystick on touch, the stick on gamepad", function()
		local keys = TutorialGlyphs.controls("KeyboardMouse", Tutorial.Glyphs) :: any
		T.equal(keys.kind, "Keys")
		T.equal(table.concat(keys.keys, ""), "WASD")
		T.equal(keys.press, "W")
		T.equal(TutorialGlyphs.controls("Touch", Tutorial.Glyphs).kind, "Joystick")
		local stick = TutorialGlyphs.controls("Gamepad", Tutorial.Glyphs) :: any
		T.equal(stick.kind, "Stick")
		T.equal(TutorialGlyphs.describe(stick), "Stick:L")
	end)

	test("menuKey: U on keyboard, D-pad right on gamepad, a tap on touch (Config.Ui.Keybinds)", function()
		local binds = Ui.Keybinds.Upgrades
		T.equal(TutorialGlyphs.describe(TutorialGlyphs.menuKey("KeyboardMouse", binds)), "Key:U")
		T.equal(TutorialGlyphs.describe(TutorialGlyphs.menuKey("Gamepad", binds)), "DPad:Right")
		T.equal(TutorialGlyphs.describe(TutorialGlyphs.menuKey("Touch", binds)), "Tap")
		-- A menu without a D-pad (Lobby button): gamepad falls back to a tap on the button.
		T.equal(TutorialGlyphs.describe(TutorialGlyphs.menuKey("Gamepad", Ui.Keybinds.Lobby)), "Tap")
		T.equal(TutorialGlyphs.describe(TutorialGlyphs.menuKey("Gamepad", { Toggle = { "ButtonY" } })), "Key:Y")
		T.equal(TutorialGlyphs.describe(TutorialGlyphs.menuKey("KeyboardMouse", nil)), "Tap")
	end)

	test("controlsRect: on touch inside the joystick zone; otherwise bottom centre, off the ball", function()
		for _, screen in SCREENS do
			local scale = Layout.scale(screen, Ui)
			local zones = Layout.zones(screen, Ui)
			for _, device in { "Touch", "KeyboardMouse", "Gamepad" } do
				if device ~= "Touch" or screen.touch then
					local glyph = TutorialGlyphs.controls(device :: any, Tutorial.Glyphs)
					local r = TutorialGlyphs.controlsRect(glyph, screen, zones.joystick, scale, Tutorial.Display)
					local label = `{screen.name} {device}`
					T.isTrue(
						inside(r, { x = 0, y = 0, width = screen.width, height = screen.height }),
						label .. " on screen"
					)
					if device == "Touch" then
						T.isTrue(inside(r, zones.joystick), label .. " inside the joystick zone")
					elseif screen.height >= 500 then
						T.equal(Layout.overlaps(r, zones.ball), false, label .. " off the ball zone")
					end
				end
			end
		end
	end)
end)

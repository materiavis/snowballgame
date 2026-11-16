--!strict
-- Concept 10.2 "Fertig, wenn …" for the layout math (issue #35 AC2-AC4), on the shipped
-- Config.Ui values and a spread of real screen sizes in ScreenGui points.

local T = require("../../TestKit")
local Layout = require("../../../src/client/Ui/Layout")
local Ui = require("../../../src/shared/Config/Ui") :: any

type Rect = Layout.Rect
type Screen = Layout.Screen

local function screen(width: number, height: number, touch: boolean): Screen
	return { width = width, height = height, touch = touch }
end

-- Landscape phones, with and without the Roblox top bar taken off the safe area.
local PHONES = {
	screen(667, 375, true), -- iPhone SE 2/3
	screen(667, 317, true), -- iPhone SE minus top bar
	screen(568, 320, true), -- iPhone SE 1st gen
	screen(568, 262, true),
	screen(740, 360, true), -- small Android
	screen(844, 390, true), -- iPhone 12-14
	screen(932, 430, true), -- iPhone Pro Max
}
local TABLETS = {
	screen(1024, 768, true),
	screen(1180, 820, true),
	screen(1366, 1024, true),
}
local DESKTOPS = {
	screen(800, 600, false),
	screen(1280, 720, false),
	screen(1366, 768, false),
	screen(1920, 1080, false),
	screen(2560, 1440, false),
}
local PORTRAIT_PHONES = {
	screen(375, 667, true),
	screen(390, 844, true),
}

local function name(s: Screen): string
	return `{s.width}x{s.height}{if s.touch then " touch" else ""}`
end

local function inside(r: Rect, s: Screen): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.width <= s.width and r.y + r.height <= s.height
end

local function each(list: { { Screen } }, fn: (Screen) -> ())
	for _, group in list do
		for _, s in group do
			fn(s)
		end
	end
end

local function hudRects(s: Screen): { [string]: Rect }
	local hud = Layout.hud(s, Ui, 1)
	return {
		coins = hud.coins,
		ballSize = hud.ballSize,
		hint = hud.hint,
		upgrades = hud.menuButtons[1],
	}
end

return T.suite("Ui Layout (10.2)", function(test)
	test("config keeps the concept's fixed numbers", function()
		T.equal(Ui.MinTouchTarget, 44)
		T.near(Ui.WindowMaxFraction, 2 / 3, 1e-9)
		T.equal(Ui.Keybinds.Upgrades.Toggle[1], "U")
		T.equal(Ui.Keybinds.Upgrades.Open[1], "DPadRight")
		T.equal(Ui.Keybinds.CloseTop[1], "ButtonB")
	end)

	test("phone detection: touch and a short side below the threshold", function()
		T.isTrue(Layout.isPhone(screen(667, 375, true), Ui))
		T.isTrue(Layout.isPhone(screen(932, 430, true), Ui))
		T.equal(Layout.isPhone(screen(1024, 768, true), Ui), false)
		T.equal(Layout.isPhone(screen(667, 375, false), Ui), false)
	end)

	test("AC3: every button is at least 44 px on every screen, after scaling", function()
		each({ PHONES, TABLETS, DESKTOPS, PORTRAIT_PHONES }, function(s)
			T.isTrue(Layout.button(s, Ui) >= 44, `button {name(s)}`)
			local hud = Layout.hud(s, Ui, 3)
			for index, r in hud.menuButtons do
				T.isTrue(r.width >= 44 and r.height >= 44, `menu button {index} {name(s)}`)
			end
			T.isTrue(Layout.window(s, Ui).closeSize >= 44, `close X {name(s)}`)
		end)
		-- A config that would scale the button below 44 px still gets 44.
		local small = table.clone(Ui)
		small.ButtonBase = 30
		T.equal(Layout.button(screen(667, 375, true), small), 44)
		T.equal(Layout.button(screen(300, 200, true), small), 44)
	end)

	test("AC4: windows use at most two thirds of width and height and stay on screen", function()
		each({ PHONES, TABLETS, DESKTOPS, PORTRAIT_PHONES }, function(s)
			local r = Layout.window(s, Ui).rect
			T.isTrue(r.width <= s.width * 2 / 3, `width {r.width} on {name(s)}`)
			T.isTrue(r.height <= s.height * 2 / 3, `height {r.height} on {name(s)}`)
			T.isTrue(r.width * r.height <= s.width * s.height * 2 / 3, `area on {name(s)}`)
			T.isTrue(inside(r, s), `inside {name(s)}`)
		end)
	end)

	test("AC2: on phones the HUD covers neither joystick, jump button nor ball", function()
		each({ PHONES, TABLETS }, function(s)
			local zones = Layout.zoneList(Layout.zones(s, Ui))
			T.equal(#zones, 3, "touch screens have three clear zones")
			for part, r in hudRects(s) do
				T.isTrue(inside(r, s), `{part} inside {name(s)}`)
				for index, zone in zones do
					T.isTrue(not Layout.overlaps(r, zone), `{part} overlaps zone {index} on {name(s)}`)
				end
			end
		end)
	end)

	test("AC2: the left-edge menu buttons sit above the joystick zone", function()
		each({ PHONES, TABLETS }, function(s)
			local joystick = Layout.zones(s, Ui).joystick :: Rect
			local last = Layout.hud(s, Ui, 1).menuButtons[1]
			T.isTrue(last.y + last.height <= joystick.y, `Upgrades button above joystick on {name(s)}`)
			T.equal(last.x, Layout.hud(s, Ui, 1).coins.x, "left edge, under Coins")
		end)
	end)

	test("AC2: on landscape phones and tablets an open window covers no clear zone", function()
		each({ PHONES, TABLETS }, function(s)
			local layout = Layout.window(s, Ui)
			T.equal(layout.coversBall, false, `coversBall on {name(s)}`)
			for index, zone in Layout.zoneList(Layout.zones(s, Ui)) do
				T.isTrue(not Layout.overlaps(layout.rect, zone), `window overlaps zone {index} on {name(s)}`)
			end
		end)
	end)

	test("portrait phones: the window never reaches the joystick, even when it must cover the ball", function()
		each({ PORTRAIT_PHONES }, function(s)
			local layout = Layout.window(s, Ui)
			local zones = Layout.zones(s, Ui)
			T.isTrue(not Layout.overlaps(layout.rect, zones.joystick :: Rect), `joystick on {name(s)}`)
		end)
	end)

	test("10.2 positions: Coins top left, ball size top centre, no overlap between HUD parts", function()
		each({ PHONES, TABLETS, DESKTOPS }, function(s)
			local hud = Layout.hud(s, Ui, 1)
			T.isTrue(hud.coins.x < s.width / 4 and hud.coins.y < s.height / 4, `coins top left {name(s)}`)
			T.near(hud.ballSize.x + hud.ballSize.width / 2, s.width / 2, 0.5, `ball size centred {name(s)}`)
			T.equal(hud.ballSize.y, hud.coins.y, "same top row")
			local rects = hudRects(s)
			local parts = { "coins", "ballSize", "hint", "upgrades" }
			for i = 1, #parts do
				for j = i + 1, #parts do
					local a, b = parts[i], parts[j]
					T.isTrue(not Layout.overlaps(rects[a], rects[b]), `{a} overlaps {b} on {name(s)}`)
				end
			end
		end)
	end)

	test("non-touch screens have no joystick or jump zone and centre the window", function()
		local s = screen(1920, 1080, false)
		local zones = Layout.zones(s, Ui)
		T.equal(zones.joystick, nil)
		T.equal(zones.jump, nil)
		local r = Layout.window(s, Ui).rect
		T.near(r.x + r.width / 2, s.width / 2, 1, "centred horizontally")
		T.near(r.y + r.height / 2, s.height / 2, 1, "centred vertically")
	end)

	test("rotation: the same device gives a valid layout in both orientations", function()
		for _, pair in { { 667, 375 }, { 932, 430 } } do
			for _, s in { screen(pair[1], pair[2], true), screen(pair[2], pair[1], true) } do
				local r = Layout.window(s, Ui).rect
				T.isTrue(inside(r, s), `inside {name(s)}`)
				T.isTrue(r.width <= s.width * 2 / 3 and r.height <= s.height * 2 / 3, `two thirds {name(s)}`)
			end
		end
	end)

	test("overlaps treats touching edges as clear", function()
		local a = { x = 0, y = 0, width = 10, height = 10 }
		T.equal(Layout.overlaps(a, { x = 10, y = 0, width = 5, height = 5 }), false)
		T.equal(Layout.overlaps(a, { x = 9, y = 9, width = 5, height = 5 }), true)
	end)
end)

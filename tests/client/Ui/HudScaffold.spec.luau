--!strict
-- #90 layout (concept 10.2 "Fertig, wenn …"): left-edge buttons for every subset of the
-- registered buttons, the progress bar and zone name under the ball size, the Lobby HUD and the
-- centre pop-up, on the shipped Config.Ui and real screen sizes in ScreenGui points.

local T = require("../../TestKit")
local Layout = require("../../../src/client/Ui/Layout")
local Ui = require("../../../src/shared/Config/Ui") :: any

type Rect = Layout.Rect
type Screen = Layout.Screen

local function screen(width: number, height: number, touch: boolean): Screen
	return { width = width, height = height, touch = touch }
end

local PHONES = {
	screen(667, 375, true),
	screen(667, 317, true), -- iPhone SE minus top bar
	screen(568, 320, true),
	screen(568, 262, true), -- the smallest landscape phone checked
	screen(740, 360, true),
	screen(844, 390, true),
	screen(932, 430, true),
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

local function name(s: Screen): string
	return `{s.width}x{s.height}{if s.touch then " touch" else ""}`
end

local function inside(r: Rect, s: Screen): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.width <= s.width and r.y + r.height <= s.height
end

local function each(groups: { { Screen } }, fn: (Screen) -> ())
	for _, group in groups do
		for _, s in group do
			fn(s)
		end
	end
end

-- Every HUD rectangle of the Simulator with `count` visible left-edge buttons.
local function simulatorParts(s: Screen, count: number): { [string]: Rect }
	local hud = Layout.hud(s, Ui, count)
	local parts: { [string]: Rect } = {
		coins = hud.coins,
		ballSize = hud.ballSize,
		progress = hud.progress,
		zoneName = hud.zoneName,
		hint = hud.hint,
	}
	for index, r in hud.menuButtons do
		parts[`button{index}`] = r
	end
	return parts
end

local function list(parts: { [string]: Rect }): { Rect }
	local result = {}
	for _, r in parts do
		table.insert(result, r)
	end
	return result
end

local function noOverlaps(parts: { [string]: Rect }, label: string)
	local names = {}
	for key in parts do
		table.insert(names, key)
	end
	table.sort(names)
	for i = 1, #names do
		for j = i + 1, #names do
			local a, b = names[i], names[j]
			T.isTrue(not Layout.overlaps(parts[a], parts[b]), `{a} overlaps {b} {label}`)
		end
	end
end

return T.suite("Ui HUD scaffold (#90, 10.2)", function(test)
	test("config: left-edge order, keys of the owner decision, every button has a label", function()
		T.equal(table.concat(Ui.LeftButtons, ","), "Upgrades,Pets,ZoneTeleport,Lobby")
		T.equal(Ui.Keybinds.Pets.Toggle[1], "P")
		T.equal(Ui.Keybinds.Pets.Open[1], "DPadLeft")
		T.equal(Ui.Keybinds.ZoneTeleport.Toggle[1], "T")
		T.equal(Ui.Keybinds.ZoneTeleport.Open[1], "DPadUp")
		T.equal(Ui.Keybinds.Lobby.Toggle[1], "L")
		T.equal(#Ui.Keybinds.Lobby.Open, 0, "Lobby has no D-pad direction")
		for _, id in Ui.LeftButtons do
			T.equal(type(Ui.Text[id]), "string", `Text.{id}`)
			T.isTrue(Ui.Keybinds[id] ~= nil, `Keybinds.{id}`)
		end
	end)

	test("AC2: every button of every subset size is at least 44 px on every screen", function()
		each({ PHONES, TABLETS, DESKTOPS }, function(s)
			for count = 0, #Ui.LeftButtons do
				local hud = Layout.hud(s, Ui, count)
				T.equal(#hud.menuButtons, count, `button count {count} {name(s)}`)
				for index, r in hud.menuButtons do
					T.isTrue(r.width >= 44 and r.height >= 44, `button {index}/{count} {name(s)}: {r.width}x{r.height}`)
				end
			end
		end)
	end)

	test("AC1: with any number of buttons nothing covers the joystick, the jump button or the ball", function()
		each({ PHONES, TABLETS }, function(s)
			local zones = Layout.zoneList(Layout.zones(s, Ui))
			for count = 0, #Ui.LeftButtons do
				for part, r in simulatorParts(s, count) do
					T.isTrue(inside(r, s), `{part} inside {name(s)} with {count}`)
					for index, zone in zones do
						T.isTrue(not Layout.overlaps(r, zone), `{part} overlaps zone {index} {name(s)} with {count}`)
					end
				end
			end
		end)
	end)

	test("no two HUD parts overlap, for every number of buttons", function()
		each({ PHONES, TABLETS, DESKTOPS }, function(s)
			for count = 0, #Ui.LeftButtons do
				noOverlaps(simulatorParts(s, count), `{name(s)} with {count}`)
			end
		end)
	end)

	test("buttons start under Coins at the left edge and keep their order", function()
		each({ PHONES, TABLETS, DESKTOPS }, function(s)
			local hud = Layout.hud(s, Ui, #Ui.LeftButtons)
			local first = hud.menuButtons[1]
			T.equal(first.x, hud.coins.x, `first button at the left edge {name(s)}`)
			T.isTrue(first.y >= hud.coins.y + hud.coins.height, `first button under Coins {name(s)}`)
			for index = 2, #hud.menuButtons do
				local before, r = hud.menuButtons[index - 1], hud.menuButtons[index]
				T.isTrue(r.x > before.x or r.y > before.y, `button {index} follows {index - 1} {name(s)}`)
			end
		end)
	end)

	test("a subset is laid out like the first buttons of the full set (no gaps for hidden ones)", function()
		local s = screen(1280, 720, false)
		local full = Layout.hud(s, Ui, 4).menuButtons
		local two = Layout.hud(s, Ui, 2).menuButtons
		for index = 1, 2 do
			T.equal(two[index].y, full[index].y, `row {index}`)
			T.equal(two[index].x, full[index].x, `column {index}`)
		end
	end)

	test("desktops and tablets keep one column; the smallest phones wrap into columns", function()
		each({ DESKTOPS }, function(s)
			for _, r in Layout.hud(s, Ui, 4).menuButtons do
				T.equal(r.x, Layout.hud(s, Ui, 4).coins.x, `one column {name(s)}`)
			end
		end)
		local small = Layout.hud(screen(568, 262, true), Ui, 4).menuButtons
		T.isTrue(small[2].x > small[1].x, "568x262 wraps")
	end)

	test("progress bar: same width as the ball size, under it; zone name under the bar", function()
		each({ PHONES, TABLETS, DESKTOPS }, function(s)
			local hud = Layout.hud(s, Ui, 1)
			T.equal(hud.progress.x, hud.ballSize.x, `bar x {name(s)}`)
			T.equal(hud.progress.width, hud.ballSize.width, `bar width {name(s)}`)
			T.isTrue(hud.progress.y >= hud.ballSize.y + hud.ballSize.height, `bar under size {name(s)}`)
			T.isTrue(hud.zoneName.y >= hud.progress.y + hud.progress.height, `name under bar {name(s)}`)
			T.isTrue(hud.zoneName.height >= Layout.px(Ui.Hud.ZoneNameMinHeight, hud.scale), `name height {name(s)}`)
		end)
	end)

	test("AC8 Lobby: Coins and Snow Coins top left, hint top, all clear of the joystick and each other", function()
		each({ PHONES, TABLETS, DESKTOPS }, function(s)
			local hud = Layout.lobbyHud(s, Ui)
			T.isTrue(hud.coins.x < s.width / 4 and hud.coins.y < s.height / 4, `coins top left {name(s)}`)
			T.equal(hud.snowCoins.x, hud.coins.x, `snow coins under coins {name(s)}`)
			T.isTrue(hud.snowCoins.y >= hud.coins.y + hud.coins.height, `snow coins below {name(s)}`)
			T.isTrue(hud.hint.width >= 44, `hint wide enough {name(s)}`)
			local parts = { coins = hud.coins, snowCoins = hud.snowCoins, hint = hud.hint }
			noOverlaps(parts, name(s))
			local zones = Layout.zones(s, Ui)
			for part, r in parts do
				T.isTrue(inside(r, s), `{part} inside {name(s)}`)
				for index, zone in { zones.joystick, zones.jump } do
					T.isTrue(not Layout.overlaps(r, zone :: Rect), `{part} overlaps zone {index} {name(s)}`)
				end
			end
		end)
	end)

	test("AC6/AC1: the pop-up is centred, on screen, and never covers the joystick, jump or HUD", function()
		each({ PHONES, TABLETS, DESKTOPS }, function(s)
			for count = 0, #Ui.LeftButtons do
				local parts = simulatorParts(s, count)
				local popup = Layout.popup(s, Ui, list(parts))
				local r = popup.rect
				local label = `{name(s)} with {count}`
				T.isTrue(inside(r, s), `inside {label}`)
				T.near(r.x + r.width / 2, s.width / 2, 1, `centred {label}`)
				T.isTrue(r.width >= Layout.px(Ui.Popup.MinWidth, Layout.scale(s, Ui)), `min width {label}`)
				T.isTrue(r.height >= Layout.px(Ui.Popup.MinHeight, Layout.scale(s, Ui)), `min height {label}`)
				local zones = Layout.zones(s, Ui)
				for index, zone in { zones.joystick, zones.jump } do
					T.isTrue(not Layout.overlaps(r, zone :: Rect), `zone {index} {label}`)
				end
				for part, other in parts do
					T.isTrue(not Layout.overlaps(r, other), `{part} {label}`)
				end
				T.equal(popup.coversBall, Layout.overlaps(r, zones.ball), `coversBall reports {label}`)
			end
		end)
	end)

	test("the pop-up avoids the ball where the screen has room above it", function()
		each({ TABLETS, DESKTOPS }, function(s)
			local popup = Layout.popup(s, Ui, list(simulatorParts(s, #Ui.LeftButtons)))
			T.equal(popup.coversBall, false, `ball clear on {name(s)}`)
		end)
	end)

	test("the Lobby pop-up keeps clear of the Lobby HUD and the touch zones", function()
		each({ PHONES, TABLETS, DESKTOPS }, function(s)
			local hud = Layout.lobbyHud(s, Ui)
			local r = Layout.popup(s, Ui, { hud.coins, hud.snowCoins, hud.hint }).rect
			for _, other in { hud.coins, hud.snowCoins, hud.hint } do
				T.isTrue(not Layout.overlaps(r, other), `HUD {name(s)}`)
			end
			local zones = Layout.zones(s, Ui)
			for index, zone in { zones.joystick, zones.jump } do
				T.isTrue(not Layout.overlaps(r, zone :: Rect), `zone {index} {name(s)}`)
			end
		end)
	end)
end)

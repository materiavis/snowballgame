--!strict
-- HUD and window layout math (concept 10.2, ADR 0008). Pure: the screen and Config.Ui are
-- passed in, every result is a pixel rectangle in ScreenGui space, so tests can check the
-- 44 px floor, the two-thirds limit and the clear zones without Roblox.

export type Rect = { x: number, y: number, width: number, height: number }
export type Screen = { width: number, height: number, touch: boolean }
export type Zones = { joystick: Rect?, jump: Rect?, ball: Rect }
export type HudLayout = {
	scale: number,
	button: number,
	coins: Rect,
	ballSize: Rect,
	hint: Rect,
	menuButtons: { Rect },
}
export type WindowLayout = {
	rect: Rect,
	titleHeight: number,
	closeSize: number,
	padding: number,
	-- True when the screen is too small to keep the window off the ball area.
	coversBall: boolean,
}

local Layout = {}

local function rect(x: number, y: number, width: number, height: number): Rect
	return { x = x, y = y, width = width, height = height }
end

function Layout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

function Layout.shortSide(screen: Screen): number
	return math.min(screen.width, screen.height)
end

function Layout.isPhone(screen: Screen, ui: any): boolean
	return screen.touch and Layout.shortSide(screen) < ui.PhoneMaxShortSide
end

function Layout.scale(screen: Screen, ui: any): number
	return math.clamp(Layout.shortSide(screen) / ui.ScaleReferenceShortSide, ui.MinScale, ui.MaxScale)
end

function Layout.px(base: number, scale: number): number
	return math.floor(base * scale + 0.5)
end

-- Rounded up, so a value scaled to 43.6 never becomes a 43 px button.
function Layout.button(screen: Screen, ui: any): number
	return math.max(ui.MinTouchTarget, math.ceil(ui.ButtonBase * Layout.scale(screen, ui)))
end

-- Joystick and jump zones only exist on touch screens; the ball zone always does.
function Layout.zones(screen: Screen, ui: any): Zones
	local w, h = screen.width, screen.height
	local cz = ui.ClearZones
	local ballW, ballH = w * cz.Ball.WidthFraction, h * cz.Ball.HeightFraction
	local ball = rect(w * cz.Ball.CentreX - ballW / 2, h * cz.Ball.CentreY - ballH / 2, ballW, ballH)
	if not screen.touch then
		return { ball = ball }
	end
	local js = cz.Joystick
	local jsW = math.min(w, math.max(js.MinWidth, w * js.WidthFraction))
	local jsH = math.min(h, math.max(js.MinHeight, h * js.HeightFraction))
	local jumpSize =
		math.min(Layout.shortSide(screen), math.max(cz.Jump.MinSize, Layout.shortSide(screen) * cz.Jump.SizeFraction))
	return {
		joystick = rect(0, h - jsH, jsW, jsH),
		jump = rect(w - jumpSize, h - jumpSize, jumpSize, jumpSize),
		ball = ball,
	}
end

function Layout.zoneList(zones: Zones): { Rect }
	local list = { zones.ball }
	if zones.joystick then
		table.insert(list, zones.joystick)
	end
	if zones.jump then
		table.insert(list, zones.jump)
	end
	return list
end

-- Coins top left, ball size top centre, load hint under the ball size, menu buttons down the
-- left edge under the coins (concept 10.2).
function Layout.hud(screen: Screen, ui: any, menuButtonCount: number): HudLayout
	local scale = Layout.scale(screen, ui)
	local button = Layout.button(screen, ui)
	local margin = Layout.px(ui.Margin, scale)
	local gap = Layout.px(ui.Gap, scale)
	local hud = ui.Hud
	local w = screen.width

	local ballW = math.min(Layout.px(hud.BallSizeWidth, scale), w - 2 * margin)
	local ballSize = rect(math.floor((w - ballW) / 2), margin, ballW, button)

	-- Coins never run into the centred ball size on narrow screens.
	local coinsW = math.min(Layout.px(hud.CoinsWidth, scale), ballSize.x - gap - margin)
	local coins = rect(margin, margin, math.max(coinsW, button), button)

	local menuW = math.max(button, Layout.px(hud.MenuButtonWidth, scale))
	local menuButtons = {}
	local y = coins.y + coins.height + gap
	for _ = 1, menuButtonCount do
		table.insert(menuButtons, rect(margin, y, menuW, button))
		y += button + gap
	end

	-- The hint sits between the left buttons and the right edge, centred where it fits.
	local leftLimit = margin + menuW + gap
	local hintW = math.min(Layout.px(hud.HintWidth, scale), w - leftLimit - margin)
	local hintX = math.max(leftLimit, math.floor((w - hintW) / 2))
	-- On short screens it gets flatter rather than reach into the ball area.
	local hintY = ballSize.y + ballSize.height + gap
	local ball = Layout.zones(screen, ui).ball
	local hintH = math.min(Layout.px(hud.HintHeight, scale), math.floor(ball.y - gap - hintY))
	local hint = rect(hintX, hintY, hintW, math.max(hintH, Layout.px(hud.HintMinHeight, scale)))

	return {
		scale = scale,
		button = button,
		coins = coins,
		ballSize = ballSize,
		hint = hint,
		menuButtons = menuButtons,
	}
end

-- Touch screens: docked to the right edge, right of the ball area and above the jump button,
-- so the joystick, the ball and jumping stay usable. Other screens: centred.
function Layout.window(screen: Screen, ui: any): WindowLayout
	local scale = Layout.scale(screen, ui)
	local button = Layout.button(screen, ui)
	local margin = Layout.px(ui.Margin, scale)
	local padding = Layout.px(ui.Window.Padding, scale)
	local w, h = screen.width, screen.height
	local maxW = math.min(Layout.px(ui.Window.MaxWidth, scale), math.floor(w * ui.WindowMaxFraction))
	local maxH = math.min(Layout.px(ui.Window.MaxHeight, scale), math.floor(h * ui.WindowMaxFraction))
	local minW = math.min(Layout.px(ui.Window.MinWidth, scale), maxW)
	local minH = math.min(Layout.px(ui.Window.MinHeight, scale), maxH)

	local zones = Layout.zones(screen, ui)
	local r: Rect
	if not screen.touch then
		r = rect(math.floor((w - maxW) / 2), math.floor((h - maxH) / 2), maxW, maxH)
	else
		local joystick = zones.joystick :: Rect
		local jump = zones.jump :: Rect
		local right = w - margin
		local width = math.min(maxW, math.floor(right - (zones.ball.x + zones.ball.width + margin)))
		if width < minW then
			-- Too narrow to avoid the ball: keep a usable width but never reach the joystick.
			width = math.min(minW, math.floor(right - (joystick.x + joystick.width + margin)))
		end
		local top = margin
		local height = math.max(minH, math.min(maxH, math.floor(jump.y - margin - top)))
		r = rect(right - width, top, width, height)
	end

	return {
		rect = r,
		titleHeight = button + padding,
		closeSize = button,
		padding = padding,
		coversBall = Layout.overlaps(r, zones.ball),
	}
end

return table.freeze(Layout)

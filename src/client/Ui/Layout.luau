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
	progress: Rect,
	zoneName: Rect,
	hint: Rect,
	menuButtons: { Rect },
}
export type LobbyLayout = {
	scale: number,
	button: number,
	coins: Rect,
	snowCoins: Rect,
	hint: Rect,
}
export type PopupLayout = {
	rect: Rect,
	-- True when the screen is too small to keep the pop-up off the ball area.
	coversBall: boolean,
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

-- Left-edge buttons (#90): one column under the coins. If the column would reach yLimit (the
-- joystick zone on touch screens), the buttons wrap into more columns, narrowed so the block
-- ends at xLimit (left of the ball zone and the top-centre parts). Every button keeps the
-- 44 px floor. Order runs down a column, then to the next one.
local function menuGrid(
	count: number,
	top: number,
	margin: number,
	gap: number,
	button: number,
	preferredWidth: number,
	yLimit: number,
	xLimit: number
): { Rect }
	local result = {}
	if count <= 0 then
		return result
	end
	local rowsFit = math.max(1, math.floor((yLimit - top + gap) / (button + gap)))
	local rows = math.min(count, rowsFit)
	local columns = math.ceil(count / rows)
	local width = preferredWidth
	if columns > 1 then
		local fit = math.floor((xLimit - margin - (columns - 1) * gap) / columns)
		width = math.max(button, math.min(preferredWidth, fit))
	end
	for index = 1, count do
		local column = (index - 1) // rows
		local row = (index - 1) % rows
		table.insert(result, rect(margin + column * (width + gap), top + row * (button + gap), width, button))
	end
	return result
end

-- Coins top left, ball size top centre with the progress bar and the zone name under it, the
-- load hint in the top row right of the ball size, menu buttons down the left edge under the
-- coins (concept 10.2). menuButtonCount is the number of visible (registered) buttons.
function Layout.hud(screen: Screen, ui: any, menuButtonCount: number): HudLayout
	local scale = Layout.scale(screen, ui)
	local button = Layout.button(screen, ui)
	local margin = Layout.px(ui.Margin, scale)
	local gap = Layout.px(ui.Gap, scale)
	local hud = ui.Hud
	local w = screen.width
	local zones = Layout.zones(screen, ui)
	local ball = zones.ball

	local ballW = math.min(Layout.px(hud.BallSizeWidth, scale), w - 2 * margin)
	local ballSize = rect(math.floor((w - ballW) / 2), margin, ballW, button)

	-- Coins never run into the centred ball size on narrow screens.
	local coinsW = math.min(Layout.px(hud.CoinsWidth, scale), ballSize.x - gap - margin)
	local coins = rect(margin, margin, math.max(coinsW, button), button)

	-- Progress bar and zone name under the ball size. The zone name gets flatter on short
	-- screens rather than reach into the ball area.
	local progressGap = Layout.px(hud.ProgressGap, scale)
	local barY = ballSize.y + ballSize.height + progressGap
	local progress = rect(ballSize.x, barY, ballW, Layout.px(hud.ProgressBarHeight, scale))
	local zoneY = progress.y + progress.height + progressGap
	local zoneH = math.min(Layout.px(hud.ZoneNameHeight, scale), math.floor(ball.y - gap - zoneY))
	local zoneName = rect(ballSize.x, zoneY, ballW, math.max(zoneH, Layout.px(hud.ZoneNameMinHeight, scale)))

	-- The hint: top row, right of the ball size, against the right margin.
	local hintLeft = ballSize.x + ballSize.width + gap
	local hintW = math.max(0, math.min(Layout.px(hud.HintWidth, scale), w - margin - hintLeft))
	local hint = rect(w - margin - hintW, margin, hintW, button)

	local menuW = math.max(button, Layout.px(hud.MenuButtonWidth, scale))
	local yLimit = if zones.joystick then zones.joystick.y else screen.height - margin
	local menuButtons = menuGrid(
		menuButtonCount,
		coins.y + coins.height + gap,
		margin,
		gap,
		button,
		menuW,
		yLimit,
		math.min(ball.x, ballSize.x) - gap
	)

	return {
		scale = scale,
		button = button,
		coins = coins,
		ballSize = ballSize,
		progress = progress,
		zoneName = zoneName,
		hint = hint,
		menuButtons = menuButtons,
	}
end

-- Lobby (#90): Coins and Snow Coins top left, one under the other; the load hint top centre,
-- pushed right of the balances where the centre is too close.
function Layout.lobbyHud(screen: Screen, ui: any): LobbyLayout
	local scale = Layout.scale(screen, ui)
	local button = Layout.button(screen, ui)
	local margin = Layout.px(ui.Margin, scale)
	local gap = Layout.px(ui.Gap, scale)
	local w = screen.width

	local coinsW = math.max(button, math.min(Layout.px(ui.Hud.CoinsWidth, scale), w - 2 * margin))
	local coins = rect(margin, margin, coinsW, button)
	local snowCoins = rect(margin, coins.y + coins.height + gap, coinsW, button)

	local leftLimit = coins.x + coins.width + gap
	local hintW = math.max(0, math.min(Layout.px(ui.Hud.HintWidth, scale), w - leftLimit - margin))
	local hint = rect(math.max(leftLimit, math.floor((w - hintW) / 2)), margin, hintW, button)

	return { scale = scale, button = button, coins = coins, snowCoins = snowCoins, hint = hint }
end

-- Centre pop-up (#90). It sits below every HUD part that crosses the vertical centre line,
-- just above the ball zone where there is room (else as high as allowed, and coversBall
-- reports the overlap). It narrows to stay clear of HUD parts beside it and of the joystick and
-- jump zones, and gets flatter if it would still reach the joystick.
function Layout.popup(screen: Screen, ui: any, avoid: { Rect }): PopupLayout
	local scale = Layout.scale(screen, ui)
	local margin = Layout.px(ui.Margin, scale)
	local gap = Layout.px(ui.Gap, scale)
	local p = ui.Popup
	local zones = Layout.zones(screen, ui)
	local centre = screen.width / 2

	local width = math.min(Layout.px(p.Width, scale), screen.width - 2 * margin)
	local minWidth = math.min(Layout.px(p.MinWidth, scale), width)
	local height = Layout.px(p.Height, scale)
	local minHeight = Layout.px(p.MinHeight, scale)

	local top = margin
	for _, r in avoid do
		if r.x < centre and r.x + r.width > centre then
			top = math.max(top, r.y + r.height + gap)
		end
	end
	local y = math.max(top, math.floor(zones.ball.y - gap - height))

	local half = width / 2
	local function keepClear(r: Rect?)
		if r == nil or not (r.y < y + height and y < r.y + r.height) then
			return
		end
		if r.x + r.width <= centre then
			half = math.min(half, centre - (r.x + r.width) - gap)
		elseif r.x >= centre then
			half = math.min(half, r.x - gap - centre)
		end
	end
	for _, r in avoid do
		keepClear(r)
	end
	keepClear(zones.joystick)
	keepClear(zones.jump)
	width = math.max(minWidth, math.floor(2 * half))

	local result = rect(math.floor(centre - width / 2), y, width, height)
	local joystick = zones.joystick
	if joystick and Layout.overlaps(result, joystick) then
		result.height = math.max(minHeight, math.floor(joystick.y - y))
	end
	return { rect = result, coversBall = Layout.overlaps(result, zones.ball) }
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

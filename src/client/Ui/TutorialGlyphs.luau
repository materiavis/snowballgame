--!strict
-- Which symbol a hint shows for the last used input device (concept 3.2, 10.1; ADR 0017).
-- Pure: the device and the configs are passed in, so the specs check every device.
--   controls(device)       the "move" symbol: key caps, the touch joystick or the gamepad stick
--   menuKey(device, binds) the symbol of a menu's key: a key cap, a D-pad direction or a tap

export type Device = "Touch" | "KeyboardMouse" | "Gamepad"

export type Controls =
	{ kind: "Keys", keys: { string }, press: string }
	| { kind: "Joystick" }
	| { kind: "Stick", cap: string }

export type MenuKey = { kind: "Key", label: string } | { kind: "DPad", direction: string } | { kind: "Tap" }

local TutorialGlyphs = {}

local DPAD_PREFIX = "DPad"

local function isGamepadKey(name: string): boolean
	return string.sub(name, 1, 6) == "Button"
		or string.sub(name, 1, #DPAD_PREFIX) == DPAD_PREFIX
		or string.sub(name, 1, 5) == "Thumb"
end

function TutorialGlyphs.controls(device: Device, glyphs: any): Controls
	if device == "Touch" then
		return { kind = "Joystick" }
	elseif device == "Gamepad" then
		return { kind = "Stick", cap = glyphs.MoveStickCap }
	end
	return { kind = "Keys", keys = glyphs.MoveKeys, press = glyphs.MoveKeys[1] }
end

-- `binds` is a Config.Ui.Keybinds entry ({ Toggle = {...}, Open = {...} }, Enum.KeyCode names).
-- Keyboard: the first keyboard key; gamepad: the first D-pad key, else a gamepad button; touch,
-- or no key for the device: a tap on the button itself.
function TutorialGlyphs.menuKey(device: Device, binds: any): MenuKey
	local names: { string } = {}
	if type(binds) == "table" then
		for _, list in { binds.Toggle, binds.Open } do
			if type(list) == "table" then
				for _, name in list do
					table.insert(names, name)
				end
			end
		end
	end
	if device == "KeyboardMouse" then
		for _, name in names do
			if not isGamepadKey(name) then
				return { kind = "Key", label = name }
			end
		end
	elseif device == "Gamepad" then
		for _, name in names do
			if string.sub(name, 1, #DPAD_PREFIX) == DPAD_PREFIX then
				return { kind = "DPad", direction = string.sub(name, #DPAD_PREFIX + 1) }
			end
		end
		for _, name in names do
			if string.sub(name, 1, 6) == "Button" then
				return { kind = "Key", label = string.sub(name, 7) }
			end
		end
	end
	return { kind = "Tap" }
end

export type Rect = { x: number, y: number, width: number, height: number }

local function px(base: number, scale: number): number
	return math.floor(base * scale + 0.5)
end

-- Where the controls symbol goes, in ScreenGui pixels. Touch: centred in the joystick zone
-- (Layout.zones), because it shows the joystick; the symbol is inert, so the thumb still
-- reaches the real joystick under it. Keyboard and gamepad: bottom centre, under the ball zone.
function TutorialGlyphs.controlsRect(
	glyph: Controls,
	screen: { width: number, height: number },
	joystick: Rect?,
	scale: number,
	display: any
): Rect
	local width, height
	if glyph.kind == "Keys" then
		local key, gap = px(display.KeySize, scale), px(display.KeyGap, scale)
		width, height = 3 * key + 2 * gap, 2 * key + gap
	else
		width = px(display.StickSize, scale)
		height = width
	end
	if glyph.kind == "Joystick" and joystick then
		width = math.min(width, joystick.width)
		height = math.min(height, joystick.height)
		local size = math.min(width, height)
		return {
			x = joystick.x + (joystick.width - size) / 2,
			y = joystick.y + (joystick.height - size) / 2,
			width = size,
			height = size,
		}
	end
	return {
		x = (screen.width - width) / 2,
		y = screen.height - px(display.BottomMargin, scale) - height,
		width = width,
		height = height,
	}
end

-- A short name for diagnostics: "Keys:W", "Joystick", "Stick:L", "Key:U", "DPad:Right", "Tap".
function TutorialGlyphs.describe(glyph: any): string
	if glyph.kind == "Keys" then
		return `Keys:{glyph.press}`
	elseif glyph.kind == "Stick" then
		return `Stick:{glyph.cap}`
	elseif glyph.kind == "Key" then
		return `Key:{glyph.label}`
	elseif glyph.kind == "DPad" then
		return `DPad:{glyph.direction}`
	end
	return glyph.kind
end

return table.freeze(TutorialGlyphs)

--!strict
-- Screen symbols of the onboarding hints (concept 10.1: arrows and symbols, no text; ADR 0017):
-- the animated finger on the controls (key caps, touch joystick, gamepad stick), a menu key
-- symbol, a pulsing ring and an arrow pointing at a HUD button. Built from Frames only, no image
-- assets; real hand art is an open point (ADR 0017). Every object is inert: not Active, not
-- Selectable, not Interactable, so touches, clicks and gamepad selection pass through to the
-- HUD and the joystick underneath.

local TweenService = game:GetService("TweenService")

export type Rect = { x: number, y: number, width: number, height: number }
export type Handle = { root: GuiObject, destroy: () -> () }

local TutorialHand = {}

local function rgb(list: { number }): Color3
	return Color3.fromRGB(list[1], list[2], list[3])
end

local function inert(gui: GuiObject)
	gui.Active = false
	gui.Selectable = false
	pcall(function()
		(gui :: any).Interactable = false
	end)
end

local function frame(name: string, parent: Instance, zIndex: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	inert(f)
	f.Parent = parent
	return f
end

local function round(gui: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = gui
end

local function loop(instance: Instance, seconds: number, goal: { [string]: any }): Tween
	local info = TweenInfo.new(seconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

local function handle(root: GuiObject, tweens: { Tween }): Handle
	return {
		root = root,
		destroy = function()
			for _, tween in tweens do
				tween:Cancel()
			end
			root:Destroy()
		end,
	}
end

-- The hint layer: same insets as the HUD (ADR 0008), so AbsolutePositions match.
function TutorialHand.gui(name: string, displayOrder: number, parent: Instance): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = displayOrder
	gui.Parent = parent
	return gui
end

-- A white rounded finger whose tip is at (0.5, 0) of its frame.
local function finger(parent: Instance, display: any, scale: number, zIndex: number): Frame
	local f = frame("Finger", parent, zIndex)
	f.Size = UDim2.fromOffset(
		math.floor(display.FingerSize[1] * scale + 0.5),
		math.floor(display.FingerSize[2] * scale + 0.5)
	)
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.BackgroundColor3 = rgb(display.HandRGB)
	round(f, UDim.new(0.5, 0))
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(display.KeyColourRGB)
	stroke.Thickness = 2
	stroke.Parent = f
	return f
end

local function keyCap(name: string, label: string, parent: Instance, size: number, display: any, zIndex: number): Frame
	local cap = frame(name, parent, zIndex)
	cap.Size = UDim2.fromOffset(size, size)
	cap.BackgroundColor3 = rgb(display.KeyColourRGB)
	cap.BackgroundTransparency = 0.1
	round(cap, UDim.new(0, math.floor(size / 6)))
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(display.ColourRGB)
	stroke.Thickness = 2
	stroke.Parent = cap
	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Text = label
	-- A key name is a symbol, not a sentence: never translated.
	text.AutoLocalize = false
	text.TextColor3 = rgb(display.KeyTextRGB)
	text.ZIndex = zIndex + 1
	inert(text)
	text.Parent = cap
	local padding = Instance.new("UIPadding")
	local inset = UDim.new(0.2, 0)
	padding.PaddingTop, padding.PaddingBottom, padding.PaddingLeft, padding.PaddingRight = inset, inset, inset, inset
	padding.Parent = text
	return cap
end

local function circle(name: string, parent: Instance, size: number, zIndex: number): Frame
	local c = frame(name, parent, zIndex)
	c.Size = UDim2.fromOffset(size, size)
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	round(c, UDim.new(0.5, 0))
	return c
end

-- The controls symbol for `glyph` (TutorialGlyphs.controls) inside `r`.
function TutorialHand.controls(parent: Instance, glyph: any, r: Rect, scale: number, display: any): Handle
	local root = frame("Controls", parent, 20)
	root.BackgroundTransparency = 1
	root.Position = UDim2.fromOffset(r.x, r.y)
	root.Size = UDim2.fromOffset(r.width, r.height)
	root:SetAttribute("Glyph", glyph.kind)
	local tweens: { Tween } = {}
	local seconds = display.PulseSeconds

	if glyph.kind == "Keys" then
		local key = math.floor(display.KeySize * scale + 0.5)
		local gap = math.floor(display.KeyGap * scale + 0.5)
		-- W above, A S D below (any four keys in the same layout).
		local spots = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }
		local pressed: Frame? = nil
		for index, label in glyph.keys do
			local spot = spots[index]
			if spot then
				local cap = keyCap(`Key{label}`, label, root, key, display, 21)
				cap.Position = UDim2.fromOffset(spot[1] * (key + gap), spot[2] * (key + gap))
				if label == glyph.press then
					pressed = cap
				end
			end
		end
		if pressed then
			table.insert(tweens, loop(pressed, seconds, { BackgroundColor3 = rgb(display.ColourRGB) }))
			local f = finger(root, display, scale, 23)
			local x = pressed.Position.X.Offset + key / 2
			local y = pressed.Position.Y.Offset + key * 0.55
			f.Position = UDim2.fromOffset(x, y)
			table.insert(tweens, loop(f, seconds, { Position = UDim2.fromOffset(x, y - key * 0.25) }))
		end
	else
		local size = math.min(r.width, r.height)
		local base = circle("Base", root, size, 21)
		base.Position = UDim2.fromScale(0.5, 0.5)
		base.BackgroundColor3 = rgb(display.KeyColourRGB)
		base.BackgroundTransparency = 0.4
		local stroke = Instance.new("UIStroke")
		stroke.Color = rgb(display.ColourRGB)
		stroke.Thickness = math.max(2, math.floor(display.RingThickness * scale))
		stroke.Parent = base
		local knobSize = math.floor(size * display.StickKnobFraction)
		local knob = circle("Knob", root, knobSize, 22)
		knob.BackgroundColor3 = rgb(display.ColourRGB)
		knob.Position = UDim2.fromScale(0.5, 0.5)
		-- Up and back: "walk forward" on either stick.
		table.insert(
			tweens,
			loop(knob, seconds, { Position = UDim2.new(0.5, 0, 0.5, -math.floor((size - knobSize) / 2)) })
		)
		if glyph.kind == "Stick" then
			local cap = Instance.new("TextLabel")
			cap.Name = "Cap"
			cap.BackgroundTransparency = 1
			cap.Size = UDim2.fromScale(0.6, 0.6)
			cap.Position = UDim2.fromScale(0.2, 0.2)
			cap.Font = Enum.Font.GothamBold
			cap.TextScaled = true
			cap.Text = glyph.cap
			cap.AutoLocalize = false
			cap.TextColor3 = rgb(display.KeyColourRGB)
			cap.ZIndex = 23
			inert(cap)
			cap.Parent = knob
		else
			local f = finger(knob, display, scale, 24)
			f.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	return handle(root, tweens)
end

-- The key symbol of a menu (TutorialGlyphs.menuKey) with its centre at (x, y).
function TutorialHand.menuKey(parent: Instance, glyph: any, x: number, y: number, scale: number, display: any): Handle
	local key = math.floor(display.KeySize * scale + 0.5)
	local root = frame("MenuKey", parent, 20)
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromOffset(x, y)
	root.Size = UDim2.fromOffset(key, key)
	root:SetAttribute("Glyph", glyph.kind)
	local tweens: { Tween } = {}
	if glyph.kind == "Key" then
		local cap = keyCap("Key", glyph.label, root, key, display, 21)
		table.insert(tweens, loop(cap, display.PulseSeconds, { BackgroundColor3 = rgb(display.ColourRGB) }))
	elseif glyph.kind == "DPad" then
		-- A plus of four arms; the arm of the direction is lit.
		local arm = math.floor(key / 3)
		local arms = {
			Up = { 1, 0 },
			Left = { 0, 1 },
			Right = { 2, 1 },
			Down = { 1, 2 },
			Centre = { 1, 1 },
		}
		for name, spot in arms do
			local f = frame(`DPad{name}`, root, 21)
			f.Size = UDim2.fromOffset(arm, arm)
			f.Position = UDim2.fromOffset(spot[1] * arm, spot[2] * arm)
			f.BackgroundColor3 = rgb(display.KeyColourRGB)
			if name == glyph.direction then
				f.BackgroundColor3 = rgb(display.ColourRGB)
				table.insert(tweens, loop(f, display.PulseSeconds, { BackgroundTransparency = 0.6 }))
			end
		end
	else
		local f = finger(root, display, scale, 22)
		f.Position = UDim2.fromScale(0.5, 0.2)
		table.insert(tweens, loop(f, display.PulseSeconds, { Position = UDim2.fromScale(0.5, 0) }))
	end
	return handle(root, tweens)
end

-- A pulsing ring around `r` (a HUD button) and an arrow on its right pointing at it.
function TutorialHand.pointAt(parent: Instance, r: Rect, scale: number, display: any): Handle
	local root = frame("PointAt", parent, 20)
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	local tweens: { Tween } = {}

	local thickness = math.max(2, math.floor(display.RingThickness * scale + 0.5))
	local ring = frame("Ring", root, 21)
	ring.BackgroundTransparency = 1
	ring.Position = UDim2.fromOffset(r.x - thickness, r.y - thickness)
	ring.Size = UDim2.fromOffset(r.width + 2 * thickness, r.height + 2 * thickness)
	round(ring, UDim.new(0, 8))
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(display.ColourRGB)
	stroke.Thickness = thickness
	stroke.Parent = ring
	table.insert(tweens, loop(stroke, display.PulseSeconds, { Transparency = 0.7 }))

	-- A "<" made of two arms; its tip nudges towards the button.
	local length = math.floor(display.PointerArmLength * scale + 0.5)
	local armThickness = math.max(3, math.floor(display.PointerArmThickness * scale + 0.5))
	local gap = math.floor(display.PointerGap * scale + 0.5)
	local tipX = r.x + r.width + gap
	local centreY = r.y + r.height / 2
	local arrow = frame("Arrow", root, 21)
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromOffset(length, length * 2)
	arrow.Position = UDim2.fromOffset(tipX, centreY - length)
	local reach = length * math.cos(math.rad(40))
	for _, side in { -1, 1 } do
		local f = frame(if side < 0 then "ArmUp" else "ArmDown", arrow, 22)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(length, armThickness)
		f.BackgroundColor3 = rgb(display.ColourRGB)
		f.Rotation = side * 40
		-- Both arms start at the tip (left edge, vertical centre) and open to the right.
		f.Position = UDim2.fromOffset(reach / 2, length + side * length * math.sin(math.rad(40)) / 2)
		round(f, UDim.new(0.5, 0))
	end
	table.insert(
		tweens,
		loop(arrow, display.PulseSeconds, { Position = UDim2.fromOffset(tipX + gap, centreY - length) })
	)
	return handle(root, tweens)
end

return table.freeze(TutorialHand)

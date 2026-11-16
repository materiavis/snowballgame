--!strict
-- Small builders for plain Instances (ADR 0008: no UI framework). Shared by the Place HUDs;
-- positions and sizes come from Layout and are applied with place()/applyWindow().

local Theme = require(script.Parent:WaitForChild("Theme"))
local Layout = require(script.Parent:WaitForChild("Layout"))

type Rect = Layout.Rect

export type Window = {
	root: Frame,
	title: TextLabel,
	close: TextButton,
	content: Frame,
}

local Ui = Theme.Config

local Components = {}

local function decorate(gui: GuiObject, scale: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Layout.px(Ui.CornerRadius, scale or 1))
	corner.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Brand
	stroke.Thickness = Ui.StrokeThickness
	stroke.Parent = gui
end

-- Text that shrinks to fit (translated strings can be longer) but never grows past its size.
local function fitText(label: TextLabel | TextButton, baseSize: number)
	label.TextScaled = true
	label.TextWrapped = true
	label:SetAttribute("BaseTextSize", baseSize)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = baseSize
	constraint.Parent = label
end

function Components.place(gui: GuiObject, r: Rect)
	gui.Position = UDim2.fromOffset(r.x, r.y)
	gui.Size = UDim2.fromOffset(r.width, r.height)
end

-- Rescales every fitted text below root to the current layout scale.
function Components.scaleText(root: Instance, scale: number)
	for _, item in root:GetDescendants() do
		if item:IsA("UITextSizeConstraint") and item.Parent then
			local base = item.Parent:GetAttribute("BaseTextSize")
			if type(base) == "number" then
				item.MaxTextSize = Layout.px(base, scale)
			end
		end
	end
end

function Components.panel(name: string, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Theme.Surface
	frame.BackgroundTransparency = Ui.PanelTransparency
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	decorate(frame)
	return frame
end

-- autoLocalize false for numbers, so translation never touches a changing value.
function Components.label(
	name: string,
	text: string,
	textSize: number,
	zIndex: number,
	options: { bold: boolean?, muted: boolean?, autoLocalize: boolean? }?
): TextLabel
	local opts = options or {}
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.BackgroundTransparency = 1
	label.Font = if opts.bold then Theme.FontBold else Theme.FontRegular
	label.TextColor3 = if opts.muted then Theme.TextMuted else Theme.Text
	label.AutoLocalize = opts.autoLocalize ~= false
	label.ZIndex = zIndex
	fitText(label, textSize)
	return label
end

-- Selectable, so gamepad navigation reaches it.
function Components.button(name: string, text: string, zIndex: number, brand: boolean?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = Theme.FontBold
	button.TextColor3 = Theme.Text
	button.BackgroundColor3 = if brand then Theme.Brand else Theme.SurfaceRaised
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Selectable = true
	button.ZIndex = zIndex
	fitText(button, Ui.TextSize.Button)
	decorate(button)
	return button
end

-- A hidden window with a title bar, an X close button and an empty content frame.
function Components.window(name: string, titleText: string): Window
	local z = Ui.ZIndex.Window
	local root = Components.panel(name, z)
	root.Visible = false
	root.BackgroundTransparency = 0
	root.Active = true -- clicks on the window do not fall through to the world

	local title = Components.label("Title", titleText, Ui.TextSize.Title, z + 1, { bold = true })
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = root

	local close = Components.button("Close", Ui.Text.Close, z + 1, true)
	close.Parent = root

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.ZIndex = z + 1
	content.ClipsDescendants = true
	content.Parent = root

	return { root = root, title = title, close = close, content = content }
end

-- Positions a window and its parts from Layout.window(). The close button keeps the full
-- 44 px floor because closeSize comes from Layout.button().
function Components.applyWindow(window: Window, layout: Layout.WindowLayout, scale: number)
	local r = layout.rect
	local p = layout.padding
	local closeSize = layout.closeSize
	Components.place(window.root, r)
	Components.place(window.close, { x = r.width - p - closeSize, y = p, width = closeSize, height = closeSize })
	Components.place(window.title, {
		x = p,
		y = p,
		width = math.max(0, r.width - 3 * p - closeSize),
		height = closeSize,
	})
	Components.place(window.content, {
		x = p,
		y = layout.titleHeight + p,
		width = math.max(0, r.width - 2 * p),
		height = math.max(0, r.height - layout.titleHeight - 2 * p),
	})
	Components.scaleText(window.root, scale)
end

return table.freeze(Components)

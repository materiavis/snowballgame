--!strict
-- Content of the pets window (concept 7.9, ADR 0008 `PetsWindow.Content`, ADR 0013): a header
-- with the equipped slots, the pet multiplier and the inventory count, then a scrolling grid of
-- pet cells. Instances only; texts and order come from PetsView.
--
-- Display only. The equip button sends `PetEquip(uid, equipped)` for its own cell, and only when
-- the cell says so; a "Slots full" button sends nothing. The server decides.
--
-- Playtest handles: PetsWindow.Content.Header.{Slots, Multiplier, Count}, PetsWindow.Content.Empty,
-- PetsWindow.Content.Grid.<uid>.{PetName, Rarity, Bonus, Equip}; each cell and its Equip button
-- carry the attribute State (Equipped, Equip, SlotsFull) and the cell the attribute Kind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local PetCatalogue = require(Shared:WaitForChild("PetCatalogue")) :: any
local PetCodec = require(Shared:WaitForChild("PetCodec"))
local Rarity = require(Shared:WaitForChild("Rarity")) :: any
local PetsView = require(script.Parent:WaitForChild("PetsView"))

local Ui = Theme.Config

local REMOTE = "PetEquip"
local STATUS_ATTRIBUTE = "DataLoadStatus"

export type Panel = {
	layout: (width: number, height: number, button: number, scale: number) -> (),
}

local PetsPanel = {}

local deps = {
	catalogue = PetCatalogue,
	rarity = Rarity,
	text = Ui.Text,
	multiplierDecimals = Ui.PetsWindow.MultiplierDecimals,
}

function PetsPanel.build(content: Frame): Panel
	local player = Players.LocalPlayer
	local names = PetsConfig.Attributes
	local z = Ui.ZIndex.Window + 2
	local cfg = Ui.PetsWindow

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.ZIndex = z
	header.Parent = content
	local slots =
		Components.label("Slots", Ui.Text.Missing, Ui.TextSize.Body, z + 1, { bold = true, autoLocalize = false })
	slots.Parent = header
	local multiplier =
		Components.label("Multiplier", Ui.Text.Missing, Ui.TextSize.Body, z + 1, { bold = true, autoLocalize = false })
	multiplier.TextColor3 = Theme.Max
	multiplier.Parent = header
	local count = Components.label("Count", Ui.Text.Missing, Ui.TextSize.Body, z + 1, { autoLocalize = false })
	count.Parent = header

	local empty = Components.label("Empty", Ui.Text.PetsEmpty, Ui.TextSize.Body, z + 1, { muted = true })
	empty.Visible = false
	empty.Parent = content

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = cfg.ScrollBarThickness
	grid.Selectable = false
	grid.ZIndex = z
	grid.Parent = content

	local remote: RemoteEvent? = nil
	task.spawn(function()
		remote = Net.waitForRemote(REMOTE) :: RemoteEvent
	end)

	local cells: { PetsView.Cell } = {}
	local frames: { [string]: Frame } = {}
	local metrics = { width = 0, height = 0, button = Ui.MinTouchTarget, scale = 1 }

	local function place()
		local scale = metrics.scale
		local button = metrics.button
		local gap = Layout.px(cfg.CellGap, scale)
		local line = Layout.px(cfg.LineHeight, scale)
		local width = metrics.width
		Components.place(header, { x = 0, y = 0, width = width, height = button })
		local third = math.floor(width / 3)
		Components.place(slots, { x = 0, y = 0, width = third, height = button })
		Components.place(multiplier, { x = third, y = 0, width = third, height = button })
		Components.place(count, { x = 2 * third, y = 0, width = width - 2 * third, height = button })
		local top = button + gap
		local area = { x = 0, y = top, width = width, height = math.max(0, metrics.height - top) }
		Components.place(empty, area)
		Components.place(grid, area)
		local inner = math.max(0, width - cfg.ScrollBarThickness - gap)
		local rects, canvas = PetsView.grid(inner, #cells, Layout.px(cfg.CellMinWidth, scale), gap, line, button)
		grid.CanvasSize = UDim2.fromOffset(0, canvas)
		for index, cell in cells do
			local frame = frames[cell.uid]
			local r = rects[index]
			if frame and r then
				frame.LayoutOrder = index
				Components.place(frame, r)
				local pad = math.floor(gap / 2)
				Components.place(
					frame:FindFirstChild("PetName") :: GuiObject,
					{ x = pad, y = pad, width = r.width - 2 * pad, height = line }
				)
				Components.place(frame:FindFirstChild("Rarity") :: GuiObject, {
					x = pad,
					y = pad + line,
					width = math.floor((r.width - 2 * pad) * 0.6),
					height = line,
				})
				Components.place(frame:FindFirstChild("Bonus") :: GuiObject, {
					x = pad + math.floor((r.width - 2 * pad) * 0.6),
					y = pad + line,
					width = math.floor((r.width - 2 * pad) * 0.4),
					height = line,
				})
				Components.place(frame:FindFirstChild("Equip") :: GuiObject, {
					x = pad,
					y = r.height - pad - button,
					width = r.width - 2 * pad,
					height = button,
				})
			end
		end
		Components.scaleText(content, scale)
	end

	local function cellFrame(cell: PetsView.Cell): Frame
		local frame = Components.panel(cell.uid, z + 1)
		frame.BackgroundColor3 = Theme.SurfaceRaised
		local name = Components.label("PetName", cell.name, Ui.TextSize.Body, z + 2, { bold = true })
		name.Parent = frame
		local rarity = Components.label("Rarity", "", Ui.TextSize.Caption, z + 2, { bold = true })
		rarity.Parent = frame
		local bonus = Components.label("Bonus", "", Ui.TextSize.Caption, z + 2, { autoLocalize = false })
		bonus.Parent = frame
		local equip = Components.button("Equip", "", z + 2)
		equip.Parent = frame
		equip.Activated:Connect(function()
			local current: PetsView.Cell? = nil
			for _, candidate in cells do
				if candidate.uid == frame.Name then
					current = candidate
				end
			end
			-- Only the uid and the wanted state are sent; "Slots full" sends nothing.
			if current == nil or current.state == "SlotsFull" or remote == nil then
				return
			end
			remote:FireServer(current.uid, not current.equipped)
		end)
		frame.Parent = grid
		return frame
	end

	local function refresh()
		local loaded = player:GetAttribute(STATUS_ATTRIBUTE) == "Loaded"
		local entries = if loaded then PetCodec.decodeInventory(player:GetAttribute(names.Inventory)) else {}
		local slotCount = player:GetAttribute(names.Slots)
		cells = PetsView.cells(entries, if type(slotCount) == "number" then slotCount else nil, deps)
		local head = PetsView.header(
			entries,
			slotCount,
			player:GetAttribute(PetsConfig.MultiplierAttribute),
			player:GetAttribute(names.InventorySize),
			loaded,
			deps
		)
		slots.Text = head.slots
		multiplier.Text = head.multiplier
		count.Text = head.count
		empty.Visible = loaded and #cells == 0

		local keep: { [string]: boolean } = {}
		for _, cell in cells do
			keep[cell.uid] = true
			local frame = frames[cell.uid] or cellFrame(cell)
			frames[cell.uid] = frame
			frame:SetAttribute("State", cell.state)
			frame:SetAttribute("Kind", cell.kind)
			local rarity = frame:FindFirstChild("Rarity") :: TextLabel
			rarity.Text = cell.rarityText
			rarity.TextColor3 = Color3.fromRGB(cell.rgb[1], cell.rgb[2], cell.rgb[3])
			local bonus = frame:FindFirstChild("Bonus") :: TextLabel
			bonus.Text = cell.bonusText
			local equip = frame:FindFirstChild("Equip") :: TextButton
			equip.Text = cell.buttonText
			equip:SetAttribute("State", cell.state)
			equip.BackgroundColor3 = if cell.state == "Equipped" then Theme.Brand else Theme.SurfaceRaised
			equip.TextColor3 = if cell.state == "SlotsFull" then Theme.TextMuted else Theme.Text
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				-- The rarity colour frames the cell; the label still names the rarity.
				stroke.Color = rarity.TextColor3
			end
		end
		for uid, frame in frames do
			if not keep[uid] then
				frame:Destroy()
				frames[uid] = nil
			end
		end
		place()
	end

	for _, name in
		{ STATUS_ATTRIBUTE, names.Inventory, names.Slots, names.InventorySize, PetsConfig.MultiplierAttribute }
	do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()

	return {
		layout = function(width: number, height: number, button: number, scale: number)
			metrics.width = width
			metrics.height = height
			metrics.button = button
			metrics.scale = scale
			place()
		end,
	}
end

return table.freeze(PetsPanel)

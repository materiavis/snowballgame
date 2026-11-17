--!strict
-- What the pets window shows (concept 7.9, 8.5, ADR 0013). Pure: catalogue, rarity display and
-- texts are passed in, so the cells, their order, their states and the grid are tested headless.
--
-- Display only. Inventory, slots and multiplier come from server-written player attributes; a
-- cell's state is a hint for the button, the server decides every equip.

export type Entry = { uid: string, kind: string, equipped: boolean }

export type Cell = {
	uid: string,
	kind: string,
	name: string,
	rarity: string,
	rarityText: string, -- "★★★ Rare": stars and name, never colour alone (8.5)
	rgb: { number },
	bonusText: string, -- "×1.22"
	equipped: boolean,
	-- Equipped: the button unequips. Equip: a slot is free. SlotsFull: the button sends nothing.
	state: "Equipped" | "Equip" | "SlotsFull",
	buttonText: string,
}

export type Header = { slots: string, multiplier: string, count: string }

export type Rect = { x: number, y: number, width: number, height: number }

export type Deps = {
	catalogue: {
		get: (kind: string) -> { name: string, egg: number, rarity: string }?,
		bonusOf: (record: any) -> number?,
		multiplierText: (value: number, decimals: number) -> string,
	},
	rarity: {
		label: (id: string) -> string,
		get: (id: string) -> { rgb: { number }, rank: number },
	},
	text: { [string]: string }, -- Config.Ui.Text
	multiplierDecimals: number,
}

local PetsView = {}

local function fill(template: string, values: { [string]: string }): string
	return (string.gsub(template, "{(%w+)}", function(key: string): string
		return values[key] or ""
	end))
end

-- Equipped first, then rarest, then name, then uid, so the order never jumps between updates.
function PetsView.cells(entries: { Entry }, slots: number?, deps: Deps): { Cell }
	local used = 0
	for _, entry in entries do
		if entry.equipped then
			used += 1
		end
	end
	local full = slots == nil or used >= slots
	local cells: { Cell } = {}
	for _, entry in entries do
		local info = deps.catalogue.get(entry.kind)
		if info then
			local bonus = deps.catalogue.bonusOf({ kind = entry.kind }) or 0
			local state: "Equipped" | "Equip" | "SlotsFull" = if entry.equipped
				then "Equipped"
				elseif full then "SlotsFull"
				else "Equip"
			table.insert(cells, {
				uid = entry.uid,
				kind = entry.kind,
				name = info.name,
				rarity = info.rarity,
				rarityText = deps.rarity.label(info.rarity),
				rgb = deps.rarity.get(info.rarity).rgb,
				bonusText = fill(deps.text.PetsBonus, {
					value = deps.catalogue.multiplierText(1 + bonus, deps.multiplierDecimals),
				}),
				equipped = entry.equipped,
				state = state,
				buttonText = if state == "Equipped"
					then deps.text.PetsUnequip
					elseif state == "SlotsFull" then deps.text.PetsSlotsFull
					else deps.text.PetsEquip,
			})
		end
	end
	table.sort(cells, function(a: Cell, b: Cell): boolean
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		local ra, rb = deps.rarity.get(a.rarity).rank, deps.rarity.get(b.rarity).rank
		if ra ~= rb then
			return ra > rb
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.uid < b.uid
	end)
	return cells
end

-- Header texts. Values that are not numbers (profile not loaded) show Text.Missing.
function PetsView.header(
	entries: { Entry },
	slots: any,
	multiplier: any,
	size: any,
	loaded: boolean,
	deps: Deps
): Header
	local text = deps.text
	if not loaded or type(slots) ~= "number" or type(multiplier) ~= "number" or type(size) ~= "number" then
		return { slots = text.Missing, multiplier = text.Missing, count = text.Missing }
	end
	local used = 0
	for _, entry in entries do
		if entry.equipped then
			used += 1
		end
	end
	return {
		slots = fill(text.PetsSlots, { used = tostring(used), total = tostring(slots) }),
		multiplier = fill(text.PetsMultiplier, {
			value = deps.catalogue.multiplierText(multiplier, deps.multiplierDecimals),
		}),
		count = fill(text.PetsCount, { count = tostring(#entries), size = tostring(size) }),
	}
end

-- Cell rectangles for `count` cells in a content area `width` wide: as many columns as fit
-- cells of at least cellMin, three lines each (two text lines and a button line of `button`).
-- Returns the rects and the canvas height.
function PetsView.grid(
	width: number,
	count: number,
	cellMin: number,
	gap: number,
	line: number,
	button: number
): ({ Rect }, number)
	local columns = math.max(1, math.floor((width + gap) / (cellMin + gap)))
	local cellWidth = math.max(0, math.floor((width - (columns - 1) * gap) / columns))
	local cellHeight = 2 * line + button + gap
	local rects: { Rect } = {}
	for index = 1, count do
		local column = (index - 1) % columns
		local row = (index - 1) // columns
		table.insert(rects, {
			x = column * (cellWidth + gap),
			y = row * (cellHeight + gap),
			width = cellWidth,
			height = cellHeight,
		})
	end
	local rows = math.ceil(count / columns)
	local height = if rows > 0 then rows * cellHeight + (rows - 1) * gap else 0
	return rects, height
end

return table.freeze(PetsView)

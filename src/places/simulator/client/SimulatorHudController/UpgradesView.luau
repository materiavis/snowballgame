--!strict
-- What each row of the Upgrades window shows (concept 7.8, ADR 0010). Pure: levels, coins and
-- the load status come from server-written player attributes and are passed in, so a headless
-- spec checks every text. Display only: whether a purchase happens is decided on the server.

export type Input = {
	-- Config.Upgrades: Order, MaxLevel
	upgrades: any,
	-- Formulas.Upgrades: cost(id, level), effect(id, level)
	formulas: any,
	-- NumberFormat.price
	formatPrice: (value: number) -> string,
	-- Config.Ui (Text, UpgradeRows)
	ui: any,
	-- DataLoadStatus attribute
	status: any,
	-- Coins attribute
	coins: any,
	-- Upgrade<Id>Level attribute per id
	levels: { [string]: any },
}

-- Buy: can be bought now. TooFewCoins: next level costs more than the balance. Max: at
-- MaxLevel. Unavailable: profile not loaded or no valid level yet.
export type State = "Buy" | "TooFewCoins" | "Max" | "Unavailable"

export type Row = {
	id: string,
	name: string,
	levelText: string,
	effectText: string,
	priceText: string,
	buttonText: string,
	state: State,
	-- True only for "Buy": the client sends the request only then.
	canBuy: boolean,
}

local UpgradesView = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isLevel(value: any, maxLevel: number): boolean
	return isFinite(value) and value % 1 == 0 and value >= 0 and value <= maxLevel
end

-- Prefix .. value .. Unit, value = effect * Scale at Decimals decimals ("16.16 studs/s").
function UpgradesView.effectValue(format: any, effect: number): string
	return `{format.Prefix}{string.format(`%.{format.Decimals}f`, effect * format.Scale)}`
end

function UpgradesView.row(input: Input, id: string): Row
	local ui = input.ui
	local text = ui.Text
	local format = ui.UpgradeRows[id]
	local maxLevel = input.upgrades.MaxLevel
	local level = input.levels[id]

	local row: Row = {
		id = id,
		name = format.Name,
		levelText = text.Missing,
		effectText = text.Missing,
		priceText = text.Missing,
		buttonText = text.UpgradeBuy,
		state = "Unavailable",
		canBuy = false,
	}
	if input.status ~= "Loaded" or not isLevel(level, maxLevel) then
		return row
	end

	row.levelText = `{level}/{maxLevel}`
	local now = UpgradesView.effectValue(format, input.formulas.effect(id, level))
	if level >= maxLevel then
		row.effectText = `{now}{format.Unit}`
		row.priceText = text.UpgradeMax
		row.buttonText = text.UpgradeMax
		row.state = "Max"
		return row
	end

	local after = UpgradesView.effectValue(format, input.formulas.effect(id, level + 1))
	row.effectText = `{now}{text.UpgradeArrow}{after}{format.Unit}`
	local price = input.formulas.cost(id, level + 1)
	row.priceText = input.formatPrice(price)
	-- The real coin check is on the server; this only says whether a click can succeed.
	if isFinite(input.coins) and input.coins >= price then
		row.state = "Buy"
		row.canBuy = true
	else
		row.state = "TooFewCoins"
		row.buttonText = text.UpgradeTooFewCoins
	end
	return row
end

function UpgradesView.rows(input: Input): { Row }
	local rows = {}
	for _, id in input.upgrades.Order do
		table.insert(rows, UpgradesView.row(input, id))
	end
	return rows
end

export type Rect = { x: number, y: number, width: number, height: number }
export type RowLayout = {
	height: number,
	gap: number,
	name: Rect,
	level: Rect,
	effect: Rect,
	price: Rect,
	buy: Rect,
}

local function rect(x: number, y: number, width: number, height: number): Rect
	return { x = x, y = y, width = width, height = height }
end

-- Rectangles inside one row of `width` px. `button` is Layout.button (already at least
-- MinTouchTarget), so the buy button keeps the 44 px floor in both directions.
function UpgradesView.layout(width: number, button: number, scale: number, ui: any): RowLayout
	local config = ui.UpgradesWindow
	local gap = math.floor(config.RowGap * scale + 0.5)
	local buyMin = math.max(button, math.floor(config.BuyMinWidth * scale + 0.5))
	local buyW = math.max(buyMin, math.floor(width * config.BuyColumnFraction))
	local infoW = math.max(0, width - buyW - gap)
	local nameW = math.floor(infoW * config.NameFraction)
	return {
		height = 2 * button,
		gap = gap,
		name = rect(0, 0, nameW, button),
		level = rect(nameW, 0, infoW - nameW, button),
		effect = rect(0, button, infoW, button),
		price = rect(infoW + gap, 0, buyW, button),
		buy = rect(infoW + gap, button, buyW, button),
	}
end

return table.freeze(UpgradesView)

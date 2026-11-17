--!strict
-- What an egg station label shows (concept 7.9, 8.5, ADR 0013). Pure: catalogue, odds, rarity
-- display and number formats are passed in, so the texts are tested headless.
--
-- The chances come from the same table the server rolls with (Rng.eggOdds), so the label can
-- never show other odds than the roll uses. The price is the same formula the server charges.

export type Entry = { id: string, weight: number }

export type OddsRow = {
	rarity: string,
	pet: string, -- the pet's name
	rarityText: string, -- "★★ Uncommon": stars and name, never colour alone (8.5)
	chance: string, -- "25%"
	rgb: { number },
}

export type Reveal = {
	name: string,
	rarityText: string,
	bonusText: string, -- "×1.1"
	rgb: { number },
}

export type Deps = {
	catalogue: {
		petFor: (egg: number, rarity: string) -> string?,
		get: (kind: string) -> { name: string, egg: number, rarity: string }?,
		bonusOf: (record: any) -> number?,
		multiplierText: (value: number, decimals: number) -> string,
	},
	rarity: {
		label: (id: string) -> string,
		get: (id: string) -> { rgb: { number } },
	},
	text: { [string]: string }, -- Config.Ui.Text
	multiplierDecimals: number,
}

local EggStationView = {}

-- "60%", "4%", "0.01%": whole chances without decimals, others with up to two.
function EggStationView.chanceText(weight: number): string
	local rounded = math.floor(weight * 100 + 0.5) / 100
	if rounded % 1 == 0 then
		return `{string.format("%d", rounded)}%`
	end
	local text = string.format("%.2f", rounded)
	text = string.gsub(text, "0+$", "")
	return `{text}%`
end

-- One row per rarity of the odds table that has a pet in this egg, in table order (lowest first).
function EggStationView.oddsRows(egg: number, odds: { Entry }, deps: Deps): { OddsRow }
	local rows: { OddsRow } = {}
	for _, entry in odds do
		local kind = deps.catalogue.petFor(egg, entry.id)
		local info = if kind then deps.catalogue.get(kind) else nil
		if info then
			table.insert(rows, {
				rarity = entry.id,
				pet = info.name,
				rarityText = deps.rarity.label(entry.id),
				chance = EggStationView.chanceText(entry.weight),
				rgb = deps.rarity.get(entry.id).rgb,
			})
		end
	end
	return rows
end

function EggStationView.priceText(price: number, formatPrice: (number) -> string, text: { [string]: string }): string
	return (string.gsub(text.EggPrice, "{price}", formatPrice(price)))
end

-- "Need 1.2K more" when the coins do not reach the price, else nil. The amount is rounded up
-- (NumberFormat.price), so the message never understates what is missing.
function EggStationView.missingText(
	price: number,
	coins: any,
	formatPrice: (number) -> string,
	text: { [string]: string }
): string?
	if type(coins) ~= "number" or coins >= price then
		return nil
	end
	return (string.gsub(text.EggNeedMore, "{amount}", formatPrice(price - coins)))
end

-- "<uid>:<kind>" from the EggLastHatch attribute.
function EggStationView.parseHatch(value: any): (string?, string?)
	if type(value) ~= "string" then
		return nil, nil
	end
	local uid, kind = string.match(value, "^([%w_%-]+):(%w+)$")
	return uid, kind
end

function EggStationView.reveal(kind: string, deps: Deps): Reveal?
	local info = deps.catalogue.get(kind)
	if info == nil then
		return nil
	end
	local bonus = deps.catalogue.bonusOf({ kind = kind }) or 0
	local value = deps.catalogue.multiplierText(1 + bonus, deps.multiplierDecimals)
	return {
		name = info.name,
		rarityText = deps.rarity.label(info.rarity),
		bonusText = (string.gsub(deps.text.PetsBonus, "{value}", value)),
		rgb = deps.rarity.get(info.rarity).rgb,
	}
end

return table.freeze(EggStationView)

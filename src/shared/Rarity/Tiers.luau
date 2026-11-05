--!strict
-- Rarity display (concept 8.5, 10.3): every tier has a colour and a symbol (stars or a crown)
-- and a name, so the UI never has to show colour alone. Pure: the config is passed to new(),
-- Rarity/init.luau binds it to Config.Rarity.

export type TierConfig = {
	Name: string,
	Stars: number,
	Symbol: string?,
	Color: { number },
	Rainbow: boolean?,
}

export type RarityConfig = {
	Order: { string },
	StarSymbol: string,
	Tiers: { [string]: TierConfig },
}

export type Info = {
	id: string,
	name: string,
	rank: number, -- 1 = lowest
	stars: number,
	symbol: string, -- "★★★" or the tier's own symbol; never empty
	rgb: { number }, -- { r, g, b } 0..255
	rainbow: boolean,
}

export type Rarity = {
	order: { string },
	isRarity: (id: any) -> boolean,
	get: (id: string) -> Info,
	-- "★★★ Rare": symbol and name together, for any label that also uses the colour.
	label: (id: string) -> string,
	compare: (a: string, b: string) -> boolean,
}

local Tiers = {}

function Tiers.new(config: RarityConfig): Rarity
	local infos: { [string]: Info } = {}
	for rank, id in config.Order do
		local tier = config.Tiers[id]
		assert(tier ~= nil, `Rarity: {id} is in Order but has no tier`)
		local symbol = if tier.Stars > 0 then string.rep(config.StarSymbol, tier.Stars) else tier.Symbol or ""
		assert(symbol ~= "", `Rarity: {id} needs stars or a symbol (concept 8.5: never colour alone)`)
		assert(#tier.Color == 3, `Rarity: {id} needs an r, g, b colour`)
		infos[id] = table.freeze({
			id = id,
			name = tier.Name,
			rank = rank,
			stars = tier.Stars,
			symbol = symbol,
			rgb = tier.Color,
			rainbow = tier.Rainbow == true,
		})
	end

	local function isRarity(id: any): boolean
		return type(id) == "string" and infos[id] ~= nil
	end

	local function get(id: string): Info
		local info = infos[id]
		if info == nil then
			error(`Rarity: unknown rarity {tostring(id)}`, 2)
		end
		return info
	end

	local function label(id: string): string
		local info = get(id)
		return `{info.symbol} {info.name}`
	end

	-- Sort helper: true if a is rarer than b (highest first).
	local function compare(a: string, b: string): boolean
		return get(a).rank > get(b).rank
	end

	return table.freeze({
		order = config.Order,
		isRarity = isRarity,
		get = get,
		label = label,
		compare = compare,
	})
end

return table.freeze(Tiers)

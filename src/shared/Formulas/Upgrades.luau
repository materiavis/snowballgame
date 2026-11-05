--!strict
-- Upgrade cost and effect (concept 7.8). Pure; Formulas/init.luau binds it to Config.Upgrades.

export type Definition = { BasePrice: number, Factor: number, Start: number, End: number }
export type UpgradesConfig = { MaxLevel: number, Definitions: { [string]: Definition } }

export type Upgrades = {
	maxLevel: number,
	cost: (id: string, level: number) -> number,
	nextCost: (id: string, currentLevel: number) -> number?,
	effect: (id: string, level: number) -> number,
}

-- Whole coins, rounded down. The tiny relative nudge keeps a product that should be whole
-- (79.99999999999999 from float maths) from losing a coin; it is far below one coin.
local function wholeCoins(value: number): number
	return math.floor(value * (1 + 1e-12))
end

local UpgradesFormulas = {}

function UpgradesFormulas.new(config: UpgradesConfig): Upgrades
	local function definition(id: string): Definition
		local found = config.Definitions[id]
		if found == nil then
			error(`Formulas.Upgrades: unknown upgrade {tostring(id)}`, 3)
		end
		return found
	end

	local function checkLevel(level: number, min: number)
		if type(level) ~= "number" or level % 1 ~= 0 or level < min or level > config.MaxLevel then
			error(`Formulas.Upgrades: level must be a whole number {min}..{config.MaxLevel}, got {tostring(level)}`, 3)
		end
	end

	-- Price of buying `level` (1 = the first purchase): BasePrice * Factor^(level - 1), in whole
	-- coins rounded down.
	local function cost(id: string, level: number): number
		local def = definition(id)
		checkLevel(level, 1)
		return wholeCoins(def.BasePrice * def.Factor ^ (level - 1))
	end

	-- Price of the next level, or nil at the maximum.
	local function nextCost(id: string, currentLevel: number): number?
		checkLevel(currentLevel, 0)
		if currentLevel >= config.MaxLevel then
			return nil
		end
		return cost(id, currentLevel + 1)
	end

	-- Effect at `level` (0..MaxLevel), linear from Start to End.
	local function effect(id: string, level: number): number
		local def = definition(id)
		checkLevel(level, 0)
		return def.Start + (def.End - def.Start) * level / config.MaxLevel
	end

	return table.freeze({
		maxLevel = config.MaxLevel,
		cost = cost,
		nextCost = nextCost,
		effect = effect,
	})
end

return table.freeze(UpgradesFormulas)

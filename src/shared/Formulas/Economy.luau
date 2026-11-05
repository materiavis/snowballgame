--!strict
-- Selling, bonuses, finds, income per minute, rebirth and Snow Coin rewards (concept 7.5, 7.7,
-- 7.10, 7.12, 7.20, 8.2, 8.3). Pure; Formulas/init.luau binds it to Config and the zone
-- formulas. Coin amounts that are paid or charged are whole coins, rounded down (ADR 0007).
-- The server always recomputes; the client may call these for previews only.

-- Bonus flags: a key of the config's multiplied or added bonus table set to true is active.
export type Flags = { [string]: boolean }

export type EconomyConfig = {
	SellMultipliedBonuses: { [string]: number },
	SellAddedBonuses: { [string]: number },
	IncomeBallsPerMinute: number,
	RebirthMinZone: number,
	RebirthCostBarriers: number,
	RebirthBonus: number,
	RebirthRankCount: number,
	SnowCoinsWin: number,
	SnowCoinsLoss: number,
	SnowCoinsPerFreeze: number,
	SnowCoinsMvp: number,
	SnowCoinsMultipliedBonuses: { [string]: number },
	SnowCoinsAddedBonuses: { [string]: number },
}

export type FindsConfig = { Values: { [string]: number } }

type ZoneValues = {
	ballValue: (sizeMetres: number) -> number,
	fullBallValue: (zone: number) -> number,
	barrierPrice: (zone: number) -> number,
}

export type Sale = {
	size: number, -- metres
	findsValue: number?, -- sum of findValue() of the finds in the ball
	petMultiplier: number?, -- Formulas.Pets.totalMultiplier
	rebirthMultiplier: number?,
	sellMultiplier: number?, -- Sell value upgrade effect
	bonus: number?, -- sellBonus(flags)
}

export type Match = {
	won: boolean,
	freezes: number,
	mvp: boolean,
	flags: Flags?, -- DoubleSnowCoins, PrivateServer, Vip, Premium
}

export type Economy = {
	sellBonus: (flags: Flags) -> number,
	findValue: (zone: number, rarity: string) -> number,
	saleCoins: (sale: Sale) -> number,
	rebirthMultiplier: (rebirths: number) -> number,
	rebirthCost: (highestUnlockedZone: number) -> number,
	canRebirth: (highestUnlockedZone: number) -> boolean,
	rebirthRank: (rebirths: number) -> number,
	incomePerMinute: (highestUnlockedZone: number, multiplier: number) -> number,
	minutesOfIncome: (minutes: number, highestUnlockedZone: number, multiplier: number) -> number,
	snowCoins: (match: Match) -> number,
}

-- Whole coins, rounded down. The tiny relative nudge keeps a product that should be whole
-- (79.99999999999999 from float maths) from losing a coin; it is far below one coin.
local function wholeCoins(value: number): number
	return math.floor(value * (1 + 1e-12))
end

local EconomyFormulas = {}

local function checkNumber(value: any, name: string, min: number)
	if type(value) ~= "number" or value ~= value or value == math.huge or value < min then
		error(`Formulas.Economy: {name} must be a finite number >= {min}, got {tostring(value)}`, 3)
	end
end

local function checkWhole(value: any, name: string)
	checkNumber(value, name, 0)
	if value % 1 ~= 0 then
		error(`Formulas.Economy: {name} must be a whole number, got {tostring(value)}`, 3)
	end
end

-- Multiplied bonuses multiply, added bonuses add up: product * (1 + sum). Unknown flags are an
-- error, so a typo never silently drops a bonus.
local function bonusOf(multiplied: { [string]: number }, added: { [string]: number }, flags: Flags): number
	local product, sum = 1, 0
	for flag, active in flags do
		if multiplied[flag] ~= nil then
			if active then
				product *= multiplied[flag]
			end
		elseif added[flag] ~= nil then
			if active then
				sum += added[flag]
			end
		else
			error(`Formulas.Economy: unknown bonus flag {tostring(flag)}`, 3)
		end
	end
	return product * (1 + sum)
end

function EconomyFormulas.new(config: EconomyConfig, finds: FindsConfig, zones: ZoneValues): Economy
	local function sellBonus(flags: Flags): number
		return bonusOf(config.SellMultipliedBonuses, config.SellAddedBonuses, flags)
	end

	-- A find is worth a fixed share of a full ball of the zone it was found in (7.7).
	local function findValue(zone: number, rarity: string): number
		local share = finds.Values[rarity]
		if share == nil then
			error(`Formulas.Economy: no find value for rarity {tostring(rarity)}`, 2)
		end
		return share * zones.fullBallValue(zone)
	end

	-- (10 * size^3 + finds) * pets * rebirth * Sell value upgrade * bonuses (7.5).
	local function saleCoins(sale: Sale): number
		local findsValue = sale.findsValue or 0
		local pets = sale.petMultiplier or 1
		local rebirth = sale.rebirthMultiplier or 1
		local upgrade = sale.sellMultiplier or 1
		local bonus = sale.bonus or 1
		checkNumber(findsValue, "findsValue", 0)
		checkNumber(pets, "petMultiplier", 1)
		checkNumber(rebirth, "rebirthMultiplier", 1)
		checkNumber(upgrade, "sellMultiplier", 1)
		checkNumber(bonus, "bonus", 0)
		return wholeCoins((zones.ballValue(sale.size) + findsValue) * pets * rebirth * upgrade * bonus)
	end

	local function rebirthMultiplier(rebirths: number): number
		checkWhole(rebirths, "rebirths")
		return 1 + config.RebirthBonus * rebirths
	end

	local function rebirthCost(highestUnlockedZone: number): number
		return config.RebirthCostBarriers * zones.barrierPrice(highestUnlockedZone)
	end

	local function canRebirth(highestUnlockedZone: number): boolean
		return highestUnlockedZone >= config.RebirthMinZone
	end

	-- Rank index 1..RebirthRankCount: one rank per rebirth, the last one stays.
	local function rebirthRank(rebirths: number): number
		checkWhole(rebirths, "rebirths")
		return math.min(rebirths + 1, config.RebirthRankCount)
	end

	-- 8.2: full balls of the highest unlocked zone per minute times all current multipliers
	-- (pets, rebirth, Sell value upgrade, bonuses), not rounded.
	local function incomePerMinute(highestUnlockedZone: number, multiplier: number): number
		checkNumber(multiplier, "multiplier", 0)
		return zones.fullBallValue(highestUnlockedZone) * config.IncomeBallsPerMinute * multiplier
	end

	-- Coin rewards "in minutes of income" (7.12), whole coins rounded down.
	local function minutesOfIncome(minutes: number, highestUnlockedZone: number, multiplier: number): number
		checkNumber(minutes, "minutes", 0)
		return wholeCoins(minutes * incomePerMinute(highestUnlockedZone, multiplier))
	end

	-- 7.20 / 8.3: (win or loss + per freeze + MVP) * multiplied bonuses * (1 + added bonuses).
	local function snowCoins(match: Match): number
		checkWhole(match.freezes, "freezes")
		local base = (if match.won then config.SnowCoinsWin else config.SnowCoinsLoss)
			+ config.SnowCoinsPerFreeze * match.freezes
			+ (if match.mvp then config.SnowCoinsMvp else 0)
		local bonus = bonusOf(config.SnowCoinsMultipliedBonuses, config.SnowCoinsAddedBonuses, match.flags or {})
		return wholeCoins(base * bonus)
	end

	return table.freeze({
		sellBonus = sellBonus,
		findValue = findValue,
		saleCoins = saleCoins,
		rebirthMultiplier = rebirthMultiplier,
		rebirthCost = rebirthCost,
		canRebirth = canRebirth,
		rebirthRank = rebirthRank,
		incomePerMinute = incomePerMinute,
		minutesOfIncome = minutesOfIncome,
		snowCoins = snowCoins,
	})
end

return table.freeze(EconomyFormulas)

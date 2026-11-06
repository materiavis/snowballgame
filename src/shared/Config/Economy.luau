--!strict
-- Coin and Snow Coin economy (concept 7.5, 7.10, 7.20, 8.1 to 8.3, 9.2 to 9.4). Startwerte.
-- Coins (Simulator) and Snow Coins (snowball fight) are separate and neither is ever sold for
-- Robux (8.1, 9.5 ✅). Robux items only change multipliers listed here.

local Economy = {
	-- Sell (7.5, 8.3 ✅): coins = (ball value + finds) * pets * rebirth * Sell value upgrade
	-- * bonuses. Multiplied bonuses: Double coins pass, Coins boost, Golden snow event.
	-- Added bonuses: VIP and Premium (+10 % each, together x1.2) (decision 15.10.).
	SellMultipliedBonuses = table.freeze({
		DoubleCoins = 2,
		CoinsBoost = 2,
		GoldenSnow = 3,
	}),
	SellAddedBonuses = table.freeze({
		Vip = 0.1,
		Premium = 0.1,
	}),

	-- Income per minute (8.2 🟦, Development may adjust after playtests): full balls of the
	-- highest unlocked zone per minute, times all current multipliers.
	IncomeBallsPerMinute = 1,

	-- Rebirth (7.10, 8.3): from zone RebirthMinZone; costs RebirthCostBarriers times the barrier
	-- price of the highest unlocked zone (🟦); every rebirth adds RebirthBonus to the coin
	-- multiplier (x1.5, x2.0, ... ✅).
	RebirthMinZone = 10,
	RebirthCostBarriers = 2,
	RebirthBonus = 0.5,
	-- Ranks (Spielraum): one per rebirth, the last one (Legend) from 8 rebirths. Rank names
	-- come with 7.10 (English names are in the concept appendix).
	RebirthRankCount = 9,

	-- Snow Coins per match (7.20, 8.3 🟦).
	SnowCoinsWin = 30,
	SnowCoinsLoss = 15,
	SnowCoinsPerFreeze = 2,
	SnowCoinsMvp = 10,
	SnowCoinsMultipliedBonuses = table.freeze({
		DoubleSnowCoins = 2,
		PrivateServer = 0.5, -- private servers give half (9.4)
	}),
	SnowCoinsAddedBonuses = table.freeze({
		Vip = 0.1,
		Premium = 0.1,
	}),

	-- Group chest in the Lobby (7.1): once per player, members of the Materiavis group only.
	GroupChestCoins = 500,
	GroupChestEggIndex = 1, -- plus one hatch from egg 1
	GroupChestSnowCoins = 100, -- plus a hat
}

return table.freeze(Economy)

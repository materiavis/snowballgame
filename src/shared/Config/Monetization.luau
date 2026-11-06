--!strict
-- Game passes, developer products and private servers (concept 9.2 to 9.4). Robux prices are
-- fixed (decision 08.10.). Coins, Snow Coins, eggs and the luck boost are never sold (9.5).
-- AssetId 0 is a placeholder: humans fill in the real ids when they publish (CLAUDE.md §9).
-- Coin and Snow Coin multipliers of these items are in Config/Economy, pet slots and
-- inventory in Config/Pets, boost durations in Config/Events.

export type Item = { Robux: number, AssetId: number, Launch: boolean }

local Monetization = {
	Gamepasses = table.freeze({
		DoubleCoins = table.freeze({ Robux = 249, AssetId = 0, Launch = true }),
		PetSlots = table.freeze({ Robux = 199, AssetId = 0, Launch = true }),
		TripleHatch = table.freeze({ Robux = 149, AssetId = 0, Launch = true }),
		AutoHatch = table.freeze({ Robux = 249, AssetId = 0, Launch = true }),
		AutoSell = table.freeze({ Robux = 199, AssetId = 0, Launch = true }),
		FastShoes = table.freeze({ Robux = 99, AssetId = 0, Launch = true }),
		BigInventory = table.freeze({ Robux = 99, AssetId = 0, Launch = true }),
		Vip = table.freeze({ Robux = 399, AssetId = 0, Launch = true }),
		DoubleSnowCoins = table.freeze({ Robux = 149, AssetId = 0, Launch = true }),
		DoubleXp = table.freeze({ Robux = 149, AssetId = 0, Launch = false }), -- Update 1
	} :: { [string]: Item }),

	DeveloperProducts = table.freeze({
		FreshSnowNow = table.freeze({ Robux = 19, AssetId = 0, Launch = true }),
		GrowthBoost = table.freeze({ Robux = 29, AssetId = 0, Launch = true }),
		CoinsBoost = table.freeze({ Robux = 39, AssetId = 0, Launch = true }),
		StarterPack = table.freeze({ Robux = 99, AssetId = 0, Launch = true }), -- once per player
		VictoryDancePack = table.freeze({ Robux = 79, AssetId = 0, Launch = true }),
		SeasonPassPremium = table.freeze({ Robux = 399, AssetId = 0, Launch = false }), -- Update 2
	} :: { [string]: Item }),
	-- Ball skins (49 to 99) and fight cosmetic packs (49 to 149) are priced per item.
	BallSkinRobux = table.freeze({ Min = 49, Max = 99 }),
	CosmeticPackRobux = table.freeze({ Min = 49, Max = 149 }),

	-- Effects that only these items have.
	FastShoesSpeedBonus = 0.25, -- +25 % walk speed, Simulator only
	TripleHatchCount = 3,

	PrivateServerRobux = 100, -- per month (proposal)
	PrivateServerMinPlayers = 2, -- matches start from 2 players, uneven teams allowed
}

return table.freeze(Monetization)

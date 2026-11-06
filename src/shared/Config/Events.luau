--!strict
-- Server events, daily rewards and boosts (concept 7.11, 7.12, 9.3). Startwerte. Seconds.

local Events = {
	-- Fresh snow: every 15 minutes for 2 minutes, double growth, announced 10 s ahead.
	FreshSnowInterval = 900,
	FreshSnowDuration = 120,
	FreshSnowAnnounce = 10,
	FreshSnowGrowthMultiplier = 2,

	-- Golden snow: about once per hour for 1 minute, every sold ball counts three times
	-- (the multiplier itself is Config.Economy.SellMultipliedBonuses.GoldenSnow).
	GoldenSnowInterval = 3600,
	GoldenSnowDuration = 60,

	-- Daily reward (7.12): the day changes for everyone at midnight UTC. Missing a day starts
	-- again at day 1. Coin rewards are minutes of the player's own income (8.2).
	DayLength = 86400,
	DailyStreak = table.freeze({
		table.freeze({ Kind = "Coins", Minutes = 10 }),
		table.freeze({ Kind = "Boost", Boost = "Growth", Duration = 900 }),
		table.freeze({ Kind = "Coins", Minutes = 20 }),
		table.freeze({ Kind = "Egg", Egg = "Highest" }), -- an egg of the highest egg station
		table.freeze({ Kind = "Coins", Minutes = 30 }),
		table.freeze({ Kind = "Boost", Boost = "Luck", Duration = 900 }), -- free, never for Robux
		table.freeze({ Kind = "Pet", Rarity = "Epic", Egg = "HighestUnlocked" }),
	}),
	-- Daily quests (Update 1): 3 random per day, each 10 to 20 minutes of play.
	DailyQuestCount = 3,

	-- Boosts (9.3): buying again extends the remaining time instead of stacking. The time only
	-- runs while the player is in the game.
	BoostDurations = table.freeze({
		Growth = 900,
		Coins = 900,
		Luck = 900,
	}),
	GrowthBoostMultiplier = 2,
	StarterPackCoinsBoost = 1800, -- 30 minutes of coins boost in the starter pack
}

return table.freeze(Events)

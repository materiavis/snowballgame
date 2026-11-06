--!strict
-- Finds in the snow (concept 7.7, 8.5). Startwerte. Values and chances per rarity are ✅.
-- Item names per world come with 7.7 (English names are in the concept appendix).

local Finds = {
	SpawnInterval = 20, -- seconds; a point spawns a find if it holds none

	-- Chance per spawned find, in percent (Rarity ids from Config/Rarity).
	Odds = table.freeze({
		Common = 60,
		Uncommon = 25,
		Rare = 10,
		Epic = 4,
		Legendary = 1,
	}),
	-- Legendary finds exist only from this zone of each world on (zones 6 to 10). Below it the
	-- Legendary chance goes to LegendaryFallback (zones 1 to 5: Common 61 %).
	LegendaryFromZoneInWorld = 6,
	LegendaryFallback = "Common",

	-- Value as a fraction of a full ball of the current zone.
	Values = table.freeze({
		Common = 0.02,
		Uncommon = 0.05,
		Rare = 0.15,
		Epic = 0.5,
		Legendary = 2,
	}),

	-- Secret find (Yeti footprint): 1 in 2,000 per spawned find, in every world. Gives a title
	-- and a ball effect, no coin value.
	SecretChance = 1 / 2000,
}

return table.freeze(Finds)

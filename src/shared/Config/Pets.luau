--!strict
-- Pets and eggs (concept 7.9, 8.3, 8.5). Startwerte, ✅ unless noted. The pet inventory start
-- size is Config.Data.InventorySize (part of the save format).

local Pets = {
	-- One egg every 5 zones: egg k sits in zone EggZones[k].
	EggZones = table.freeze({ 1, 5, 11, 15, 21, 25, 31, 35, 41, 45 }),
	LaunchEggCount = 2,
	-- Egg price: EggPriceBalls full balls of the egg's zone.
	EggPriceBalls = 3,

	-- Bonus of the common pet in egg k: CommonBonusBase * CommonBonusGrowth^(k - 1).
	CommonBonusBase = 0.1,
	CommonBonusGrowth = 2,
	-- Bonus per rarity relative to the common pet of the same egg.
	RarityPower = table.freeze({
		Common = 1,
		Uncommon = 1.5,
		Rare = 2.2,
		Epic = 3.5,
		Legendary = 7,
	}),

	-- Hatch chances in percent. LuckOdds apply while the free luck boost runs (🟦, 8.5).
	Odds = table.freeze({
		Common = 60,
		Uncommon = 25,
		Rare = 10,
		Epic = 4,
		Legendary = 1,
	}),
	LuckOdds = table.freeze({
		Common = 55,
		Uncommon = 25,
		Rare = 10,
		Epic = 8,
		Legendary = 2,
	}),

	-- Secret pet (Golden Yeti): 1 in 10,000 per hatch, in every egg from SecretPetFromEgg on
	-- (eggs of world 2 and later), SecretPetPower times the Legendary pet of its egg.
	SecretPetChance = 1 / 10000,
	SecretPetFromEgg = 3,
	SecretPetPower = 3,

	-- Variants. Frosty: 1 in 50 at hatch, +50 % bonus. Gold: 5 equal pets, double bonus.
	-- Rainbow (later): 5 gold pets, five times the bonus.
	FrostyChance = 1 / 50,
	FrostyBonus = 0.5,
	MergeCount = 5,
	VariantMultipliers = table.freeze({
		normal = 1,
		gold = 2,
		rainbow = 5,
	}),

	-- Equip slots: start, +1 at zone 10, +1 at zone 20, +3 with the game pass, at most 8.
	SlotsStart = 3,
	SlotsByZone = table.freeze({
		table.freeze({ Zone = 10, Slots = 1 }),
		table.freeze({ Zone = 20, Slots = 1 }),
	}),
	SlotsGamepass = 3,
	SlotsMax = 8,

	-- Inventory expansion with coins (❓ Q11, Development decides; concept default): +10 slots
	-- for the value of 10 full balls of the highest unlocked zone, up to 150 slots.
	InventoryExpansionSlots = 10,
	InventoryExpansionPriceBalls = 10,
	InventoryExpansionMax = 150,
	InventoryGamepassSlots = 100, -- Big inventory game pass (9.2)
}

return table.freeze(Pets)

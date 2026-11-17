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

	-- Pet catalogue (concept 7.9, appendix "Pet-Katalog", English names from the appendix "Englische
	-- Namen"). The key is the pet's `kind` in the save format (sim.pets[uid].kind, ADR 0003), so a
	-- key is never renamed. Egg 1 only in the Vertical Slice; Egg 2 comes with #103 (ADR 0013).
	Catalogue = table.freeze({
		SnowHare = table.freeze({ Name = "Snow Hare", Egg = 1, Rarity = "Common" }),
		AlpineChough = table.freeze({ Name = "Alpine Chough", Egg = 1, Rarity = "Uncommon" }),
		Marmot = table.freeze({ Name = "Marmot", Egg = 1, Rarity = "Rare" }),
		RedFox = table.freeze({ Name = "Red Fox", Egg = 1, Rarity = "Epic" }),
		SnowyOwl = table.freeze({ Name = "Snowy Owl", Egg = 1, Rarity = "Legendary" }),
	}),

	-- Server-written player attributes (ADR 0013). MultiplierAttribute is the interface to selling
	-- (#38): 1 + the bonuses of the equipped pets, written on every server on load and after every
	-- equip change. The others are the client contract of the pets window and the followers.
	MultiplierAttribute = "PetMultiplier",
	Attributes = table.freeze({
		Inventory = "PetInventory", -- "<uid>:<kind>:<0|1>;..." (PetCodec)
		Equipped = "PetEquipped", -- "<uid>:<kind>;..." (PetCodec), read by every client
		Slots = "PetSlots", -- equip slots now
		InventorySize = "PetInventorySize", -- how many pets fit
	}),

	-- Equipped pets following their player (concept 7.9 Spielraum "Laufverhalten", "vereinfachte
	-- Darstellung fremder Pets", ADR 0003 R2). Placeholder shapes until the pet models exist.
	-- Distances in studs, rates per second. Not design values, look and feel only.
	Follow = table.freeze({
		-- PlaceRole values where pets follow. The Lobby joins with #103; never the Arena (15.10).
		Roles = table.freeze({ Simulator = true }),
		BackDistance = 5, -- behind the character
		Spacing = 3.5, -- side by side
		RowDepth = 3, -- between rows when more pets than PerRow are equipped
		PerRow = 3,
		Sharpness = 10, -- how fast a pet closes the gap (1 / s, exponential smoothing)
		SnapDistance = 60, -- further than this from its place: jump there (teleport, respawn)
		BobHeight = 0.3,
		BobSpeed = 4, -- radians per second
		-- Own pets: body and head, a name label, every frame.
		OwnBodySize = 2,
		OwnHeadSize = 1.2,
		LabelMaxDistance = 40,
		-- Pets of other players (R2): one part, no label, no bob, a lower update rate, hidden far away.
		ForeignBodySize = 2,
		ForeignUpdateRate = 10,
		ForeignMaxDistance = 150,
	}),
}

return table.freeze(Pets)

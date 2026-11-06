--!strict
-- Concept 7.9 egg table, pet bonuses, slots and the Q11 default (issue #27 AC1).

local T = require("../../TestKit")
local E = require("../../helpers/Economy")

local Pets = E.Pets
local Zones = E.Zones

-- 7.9 table: zone, multiplier of the common and the legendary pet ("×1.1", "×1.7", ...).
-- The concept rounds the larger legendary values (12.2 -> 12, 45.8 -> 46, 359.4 -> 360).
local EGG_TABLE = {
	{ zone = 1, common = 1.1, legendary = 1.7 },
	{ zone = 5, common = 1.2, legendary = 2.4 },
	{ zone = 11, common = 1.4, legendary = 3.8 },
	{ zone = 15, common = 1.8, legendary = 6.6 },
	{ zone = 21, common = 2.6, legendary = 12 },
	{ zone = 25, common = 4.2, legendary = 23 },
	{ zone = 31, common = 7.4, legendary = 46 },
	{ zone = 35, common = 14, legendary = 90 },
	{ zone = 41, common = 27, legendary = 180 },
	{ zone = 45, common = 52, legendary = 360 },
}

return T.suite("Formulas.Pets (7.9, 8.4)", function(test)
	test("8.4: Egg 1 costs exactly 240, Egg 2 ca. 3.5K", function()
		T.equal(Pets.eggPrice(1), 240)
		T.near(Pets.eggPrice(2), 3.5e3, 3.5e3 * 0.05, "egg 2")
		T.equal(Pets.eggPrice(2), 3492)
	end)

	test("7.9: egg price = 3 full balls of the egg's zone, for all 10 eggs", function()
		T.equal(Pets.eggCount, 10)
		for egg = 1, 10 do
			T.equal(
				Pets.eggPrice(egg),
				math.floor(3 * Zones.fullBallValue(Pets.eggZone(egg)) * (1 + 1e-12)),
				`egg {egg}`
			)
		end
	end)

	test("7.9 egg table: zones and common/legendary multipliers", function()
		for egg, row in EGG_TABLE do
			T.equal(Pets.eggZone(egg), row.zone, `egg {egg} zone`)
			local common = 1 + Pets.petBonus({ egg = egg, rarity = "Common" })
			local legendary = 1 + Pets.petBonus({ egg = egg, rarity = "Legendary" })
			T.near(common, row.common, 0.05 * row.common, `egg {egg} common`)
			T.near(legendary, row.legendary, 0.02 * row.legendary, `egg {egg} legendary`)
		end
		T.near(Pets.petBonus({ egg = 1, rarity = "Common" }), 0.1, 1e-12, "0.1 * 2^0")
		T.near(Pets.petBonus({ egg = 4, rarity = "Common" }), 0.8, 1e-12, "0.1 * 2^3")
	end)

	test("8.3 rarity powers 1 / 1.5 / 2.2 / 3.5 / 7", function()
		local base = Pets.petBonus({ egg = 2, rarity = "Common" })
		local expected = { Common = 1, Uncommon = 1.5, Rare = 2.2, Epic = 3.5, Legendary = 7 }
		for rarity, power in expected do
			T.near(Pets.petBonus({ egg = 2, rarity = rarity }), base * power, 1e-12, rarity)
		end
	end)

	test("7.9: equipped bonuses add up (x1.4 + x2.0 + x3.0 = x4.4)", function()
		T.near(Pets.totalMultiplier({ 0.4, 1.0, 2.0 }), 4.4, 1e-12)
		T.equal(Pets.totalMultiplier({}), 1, "no pets: x1")
	end)

	test("8.3 variants: gold x2, rainbow x5, frosty +50 %, golden yeti 3 x legendary", function()
		local legendary = Pets.petBonus({ egg = 3, rarity = "Legendary" })
		local common = Pets.petBonus({ egg = 3, rarity = "Common" })
		T.near(Pets.petBonus({ egg = 3, rarity = "Common", variant = "gold" }), 2 * common, 1e-12, "gold")
		T.near(Pets.petBonus({ egg = 3, rarity = "Common", variant = "rainbow" }), 5 * common, 1e-12, "rainbow")
		T.near(Pets.petBonus({ egg = 3, rarity = "Common", frosty = true }), 1.5 * common, 1e-12, "frosty")
		T.near(Pets.petBonus({ egg = 3, rarity = "Secret" }), 3 * legendary, 1e-12, "golden yeti")
		T.throws(function()
			Pets.petBonus({ egg = 3, rarity = "Mythic" })
		end, "unknown rarity")
		T.throws(function()
			Pets.petBonus({ egg = 3, rarity = "Common", variant = "shiny" })
		end, "unknown variant")
		T.throws(function()
			Pets.petBonus({ egg = 11, rarity = "Common" })
		end, "egg must be")
	end)

	test("7.9 slots: 3, +1 at zone 10, +1 at zone 20, +3 with the pass, at most 8", function()
		T.equal(Pets.equipSlots(1, false), 3)
		T.equal(Pets.equipSlots(10, false), 4)
		T.equal(Pets.equipSlots(20, false), 5)
		T.equal(Pets.equipSlots(9, true), 6)
		T.equal(Pets.equipSlots(20, true), 8)
		T.equal(Pets.equipSlots(50, true), 8, "never above the maximum")
	end)

	test("Q11 default: +10 slots for 10 full balls of the highest zone, up to 150", function()
		T.equal(Pets.inventoryExpansionPrice(1), 800)
		T.equal(Pets.inventoryExpansionPrice(3), math.floor(10 * Zones.fullBallValue(3)))
		T.isTrue(Pets.canExpandInventory(140), "140 -> 150")
		T.equal(Pets.canExpandInventory(150), false, "150 is the end")
	end)
end)

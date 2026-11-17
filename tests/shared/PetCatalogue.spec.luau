--!strict
-- The shipped pet catalogue (concept 7.9, appendix English names, ADR 0013 AC9): Egg 1 holds
-- Snow Hare, Alpine Chough, Marmot, Red Fox and Snowy Owl from common to legendary, with the
-- bonuses of the 7.9 table, and a broken catalogue fails at load.

local T = require("../TestKit")
local E = require("../helpers/Economy")
local P = require("../helpers/Pets")
local Catalogue = require("../../src/shared/PetCatalogue/Catalogue")
local PetCodec = require("../../src/shared/PetCodec")

local catalogue = P.Catalogue

return T.suite("PetCatalogue and PetCodec (7.9, ADR 0013)", function(test)
	test("Egg 1: five pets, one per rarity, English names", function()
		local expected = {
			{ "SnowHare", "Snow Hare", "Common" },
			{ "AlpineChough", "Alpine Chough", "Uncommon" },
			{ "Marmot", "Marmot", "Rare" },
			{ "RedFox", "Red Fox", "Epic" },
			{ "SnowyOwl", "Snowy Owl", "Legendary" },
		}
		local pets = catalogue.petsOf(1)
		T.equal(#pets, 5)
		for index, row in expected do
			T.equal(pets[index].id, row[1])
			T.equal(pets[index].name, row[2])
			T.equal(pets[index].rarity, row[3])
			T.equal(catalogue.petFor(1, row[3]), row[1])
		end
		T.equal(catalogue.petFor(1, "Secret"), nil, "no secret pet in world 1")
	end)

	test("7.9 table: Egg 1 common x1.1 ... legendary x1.7", function()
		local function multiplier(kind: string): number
			return 1 + (catalogue.bonusOf({ kind = kind }) :: number)
		end
		T.near(multiplier("SnowHare"), 1.1, 1e-12)
		T.near(multiplier("AlpineChough"), 1.15, 1e-12)
		T.near(multiplier("Marmot"), 1.22, 1e-12)
		T.near(multiplier("RedFox"), 1.35, 1e-12)
		T.near(multiplier("SnowyOwl"), 1.7, 1e-12)
		T.equal(catalogue.multiplierText(multiplier("SnowHare"), 2), "1.1")
		T.equal(catalogue.multiplierText(1.15, 2), "1.15")
		T.equal(catalogue.multiplierText(4.4, 2), "4.4")
		T.equal(catalogue.multiplierText(2, 2), "2")
	end)

	test("only Egg 1 is on sale; the egg comes from the zone", function()
		T.isTrue(catalogue.isAvailable(1))
		T.equal(catalogue.isAvailable(2), false, "Egg 2 is #103")
		T.equal(catalogue.isAvailable(1.5), false)
		T.equal(catalogue.isAvailable("1"), false)
		T.equal(catalogue.eggName(1), "Egg 1")
		T.equal(catalogue.eggForZone(1), 1)
		T.equal(catalogue.eggForZone(5), 2)
		T.equal(catalogue.eggForZone(2), nil)
		T.equal(catalogue.eggForZone("1"), nil)
	end)

	test("bonusOf refuses records that are not valid pets", function()
		T.equal(catalogue.bonusOf(nil), nil)
		T.equal(catalogue.bonusOf({ kind = "Dragon" }), nil)
		T.equal(catalogue.bonusOf({ kind = "SnowHare", variant = "sparkly" }), nil)
		T.equal(catalogue.bonusOf({ kind = "SnowHare", frosty = "yes" }), nil)
		T.near(catalogue.bonusOf({ kind = "SnowHare", variant = "normal", frosty = false }) :: number, 0.1, 1e-12)
	end)

	test("a broken catalogue fails at load", function()
		local function build(pets: any, eggs: any)
			return Catalogue.new(pets, eggs, E.Config.Rarity.Order, E.Pets.petBonus)
		end
		local base = E.Config.Pets
		local function with(entries: any): any
			local copy = table.clone(base)
			copy.Catalogue = entries
			return copy
		end
		local twoCommons = table.clone(base.Catalogue)
		twoCommons.Extra = { Name = "Extra", Egg = 1, Rarity = "Common" }
		T.throws(function()
			build(with(twoCommons), P.EggsConfig)
		end, "two Common")
		local missingOwl = table.clone(base.Catalogue)
		missingOwl.SnowyOwl = nil
		T.throws(function()
			build(with(missingOwl), P.EggsConfig)
		end, "no Legendary pet")
		T.throws(function()
			build(base, { Available = { [2] = { Name = "Egg 2" } } })
		end, "egg 2 is available")
	end)

	test("PetCodec round-trips inventory and equipped lists and skips malformed parts", function()
		local entries = {
			{ uid = "1001_6553f100_0001", kind = "SnowHare", equipped = true },
			{ uid = "-1_6553f100_0002", kind = "RedFox", equipped = false },
		}
		local text = PetCodec.encodeInventory(entries)
		T.equal(text, "1001_6553f100_0001:SnowHare:1;-1_6553f100_0002:RedFox:0")
		local back = PetCodec.decodeInventory(text)
		T.equal(#back, 2)
		T.equal(back[2].uid, "-1_6553f100_0002")
		T.equal(back[2].equipped, false)
		T.equal(PetCodec.encodeEquipped({ entries[1] }), "1001_6553f100_0001:SnowHare")
		T.equal(PetCodec.decodeEquipped("a:SnowHare;b:RedFox")[2].kind, "RedFox")
		T.equal(#PetCodec.decodeInventory("a:SnowHare:2;b:c;d:e:f:1;x y:SnowHare:1;ok:Marmot:1"), 1)
		T.equal(#PetCodec.decodeInventory(nil), 0)
		T.equal(PetCodec.encodeInventory({ { uid = "bad;uid", kind = "SnowHare", equipped = true } }), "")
	end)
end)

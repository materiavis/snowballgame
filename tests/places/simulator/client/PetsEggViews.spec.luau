--!strict
-- Client display rules of #41 (AC3, ADR 0013): the egg station label shows every pet of Egg 1
-- with its rarity (stars and name) and chance and the price before the purchase, the missing
-- amount rounds up ("Need 1.2K more"), and the pets window orders cells and reports slot states.

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local P = require("../../../helpers/Pets")
local UiConfig = require("../../../../src/shared/Config/Ui")
local EggStationView = require("../../../../src/places/simulator/client/EggStationController/EggStationView")
local PetsView = require("../../../../src/places/simulator/client/PetsWindowController/PetsView")

local deps = {
	catalogue = P.Catalogue,
	rarity = E.Rarity,
	text = UiConfig.Text,
	multiplierDecimals = UiConfig.PetsWindow.MultiplierDecimals,
}

return T.suite("Egg station label and pets window views (ADR 0013)", function(test)
	test("AC3: the label lists every Egg 1 pet with stars, rarity name and its chance", function()
		local rows = EggStationView.oddsRows(1, E.Odds.eggOdds(1, false), deps :: any)
		local expected = {
			{ "Snow Hare", "★ Common", "60%" },
			{ "Alpine Chough", "★★ Uncommon", "25%" },
			{ "Marmot", "★★★ Rare", "10%" },
			{ "Red Fox", "★★★★ Epic", "4%" },
			{ "Snowy Owl", "★★★★★ Legendary", "1%" },
		}
		T.equal(#rows, 5)
		for index, row in expected do
			T.equal(rows[index].pet, row[1])
			T.equal(rows[index].rarityText, row[2])
			T.equal(rows[index].chance, row[3])
			T.equal(#rows[index].rgb, 3)
		end
		T.equal(EggStationView.priceText(240, E.NumberFormat.price, UiConfig.Text), "240 Coins")
	end)

	test("chance text: whole numbers plain, fractions with up to two decimals", function()
		T.equal(EggStationView.chanceText(60), "60%")
		T.equal(EggStationView.chanceText(0.01), "0.01%")
		T.equal(EggStationView.chanceText(59.994), "59.99%")
		T.equal(EggStationView.chanceText(2.5), "2.5%")
	end)

	test("missing coins: rounded up, nil when affordable or unknown", function()
		T.equal(EggStationView.missingText(240, 100, E.NumberFormat.price, UiConfig.Text), "Need 140 more")
		T.equal(EggStationView.missingText(2400, 1250, E.NumberFormat.price, UiConfig.Text), "Need 1.2K more")
		T.equal(EggStationView.missingText(240, 240, E.NumberFormat.price, UiConfig.Text), nil)
		T.equal(EggStationView.missingText(240, nil, E.NumberFormat.price, UiConfig.Text), nil)
	end)

	test("hatch reveal: EggLastHatch parses, the pet shows with rarity and bonus", function()
		local uid, kind = EggStationView.parseHatch("1001_6553f100_0001:Marmot")
		T.equal(uid, "1001_6553f100_0001")
		T.equal(kind, "Marmot")
		T.equal(EggStationView.parseHatch("garbage"), nil)
		local reveal = EggStationView.reveal("Marmot", deps :: any) :: any
		T.equal(reveal.name, "Marmot")
		T.equal(reveal.rarityText, "★★★ Rare")
		T.equal(reveal.bonusText, "×1.22")
		T.equal(EggStationView.reveal("Dragon", deps :: any), nil)
	end)

	test("pets window: equipped first, then rarest; slot states and button texts", function()
		local entries = {
			{ uid = "a", kind = "SnowHare", equipped = false },
			{ uid = "b", kind = "SnowyOwl", equipped = false },
			{ uid = "c", kind = "Marmot", equipped = true },
		}
		local cells = PetsView.cells(entries, 3, deps :: any)
		T.equal(cells[1].uid, "c", "equipped first")
		T.equal(cells[2].uid, "b", "then the legendary")
		T.equal(cells[3].uid, "a")
		T.equal(cells[1].state, "Equipped")
		T.equal(cells[1].buttonText, "Unequip")
		T.equal(cells[2].state, "Equip")
		T.equal(cells[2].rarityText, "★★★★★ Legendary")
		T.equal(cells[2].bonusText, "×1.7")
		local full = PetsView.cells(entries, 1, deps :: any)
		T.equal(full[2].state, "SlotsFull")
		T.equal(full[2].buttonText, "Slots full")
		T.equal(full[1].state, "Equipped", "an equipped pet can always be unequipped")
		local unknownSlots = PetsView.cells(entries, nil, deps :: any)
		T.equal(unknownSlots[2].state, "SlotsFull", "no slot count yet: nothing can be equipped")
	end)

	test("pets window header: slots used/total, multiplier, count; dashes while not loaded", function()
		local entries =
			{ { uid = "c", kind = "Marmot", equipped = true }, { uid = "d", kind = "SnowHare", equipped = false } }
		local head = PetsView.header(entries, 3, 1.22, 50, true, deps :: any)
		T.equal(head.slots, "Equipped 1/3")
		T.equal(head.multiplier, "Coins ×1.22")
		T.equal(head.count, "2/50 pets")
		local missing = PetsView.header(entries, 3, 1.22, 50, false, deps :: any)
		T.equal(missing.slots, UiConfig.Text.Missing)
		T.equal(missing.multiplier, UiConfig.Text.Missing)
	end)

	test("pets window grid: columns that fit, every button line at least 44 px", function()
		local rects, height = PetsView.grid(320, 5, 150, 8, 22, 44)
		T.equal(#rects, 5)
		T.equal(rects[1].width, 156, "two columns of (320 - 8) / 2")
		T.equal(rects[3].y, rects[1].height + 8, "third cell in the second row")
		T.isTrue(rects[1].height >= 44 + 2 * 22)
		T.equal(height, 3 * rects[1].height + 2 * 8)
		local narrow = PetsView.grid(100, 2, 150, 8, 22, 44)
		T.equal(narrow[2].x, 0, "one column when even one cell does not fit")
		local _, none = PetsView.grid(320, 0, 150, 8, 22, 44)
		T.equal(none, 0)
	end)
end)

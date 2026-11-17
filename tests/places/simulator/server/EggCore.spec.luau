--!strict
-- EggCore rules (#41 AC2, AC5, AC8, AC11, ADR 0013): price 240 for Egg 1, the refusal order, the
-- double tap as one purchase (concept 6.5), the forced roll switch, and 10,000 openings through
-- the real purchase path within 1 percentage point of the chances.

local T = require("../../../TestKit")
local Distribution = require("../../../helpers/Distribution")
local E = require("../../../helpers/Economy")
local P = require("../../../helpers/Pets")
local DataConfig = require("../../../../src/shared/Config/Data")
local Schema = require("../../../../src/server/Services/DataService/Schema")

local USER = 1001
local schema = Schema.new(DataConfig)
local OPENINGS = 10000
local TOLERANCE_PP = 1

local function setup(options: any?): (any, P.Game)
	local profile = schema.newProfile()
	local game = P.on(function(userId: number): any
		return if userId == USER then profile else nil
	end, options)
	return profile, game
end

local function petCount(profile: any): number
	local count = 0
	for _ in profile.sim.pets do
		count += 1
	end
	return count
end

return T.suite("EggCore (7.9, 6.5, ADR 0013)", function(test)
	test("Egg 1 costs 240 coins and adds one pet of Egg 1", function()
		T.equal(E.Pets.eggPrice(1), 240)
		local profile, game = setup()
		game.currency.add(USER, "Coins", 300, "Sell")
		local ok, uid = game.eggs.purchase(USER, 1, "Remote")
		T.isTrue(ok)
		T.equal(game.currency.get(USER, "Coins"), 60)
		local record = profile.sim.pets[uid]
		T.equal(P.Catalogue.get(record.kind).egg, 1)
		T.equal(record.frosty, false, "no Frosty in this slice (#103)")
		local event = game.eggEvents[#game.eggEvents]
		T.equal(event.kind, "Hatched")
		T.equal(event.price, 240)
		T.equal(event.pet, record.kind)
	end)

	test("refusals change nothing: bad egg, egg not on sale, not loaded, too few coins, full", function()
		local profile, game = setup()
		game.currency.add(USER, "Coins", 1000, "Sell")
		for _, egg in { 0, 11, 1.5, "1", nil :: any } do
			T.equal(select(2, game.eggs.purchase(USER, egg, "Remote")), "BadEgg")
		end
		T.equal(select(2, game.eggs.purchase(USER, 2, "Remote")), "NotAvailable", "Egg 2 is #103")
		T.equal(select(2, game.eggs.purchase(9999, 1, "Remote")), "NotLoaded")
		T.equal(game.currency.get(USER, "Coins"), 1000)

		local _, poor = setup()
		poor.currency.add(USER, "Coins", 239, "Sell")
		T.equal(select(2, poor.eggs.purchase(USER, 1, "Remote")), "Insufficient")
		T.equal(poor.currency.get(USER, "Coins"), 239)

		profile.sim.inventorySize = 0
		T.equal(select(2, game.eggs.purchase(USER, 1, "Remote")), "InventoryFull")
		T.equal(game.currency.get(USER, "Coins"), 1000, "a full inventory is refused before any coin is spent")
		T.equal(petCount(profile), 0)
	end)

	test("AC11 6.5: an egg tapped twice is one purchase, even with coins for two", function()
		local profile, game = setup()
		game.currency.add(USER, "Coins", 480, "Sell")
		T.isTrue((game.eggs.purchase(USER, 1, "Remote")))
		T.equal(select(2, game.eggs.purchase(USER, 1, "Remote")), "Busy")
		T.equal(petCount(profile), 1)
		T.equal(game.currency.get(USER, "Coins"), 240)
		game.clock.advance(P.EggsConfig.HatchCooldownSeconds - 0.01)
		T.equal(select(2, game.eggs.purchase(USER, 1, "Remote")), "Busy", "still inside the cooldown")
		game.clock.advance(0.02)
		T.isTrue((game.eggs.purchase(USER, 1, "Remote")), "a deliberate second hatch works")
		T.equal(petCount(profile), 2)
		T.equal(game.currency.get(USER, "Coins"), 0)
	end)

	test("a refused purchase does not start the cooldown", function()
		local _, game = setup()
		game.currency.add(USER, "Coins", 100, "Sell")
		T.equal(select(2, game.eggs.purchase(USER, 1, "Remote")), "Insufficient")
		game.currency.add(USER, "Coins", 200, "Sell")
		T.isTrue((game.eggs.purchase(USER, 1, "Remote")), "the next tap after topping up works at once")
	end)

	test("forced roll (EggForceRarity) picks that rarity; an unknown one rolls normally", function()
		local forced: string? = "Legendary"
		local profile, game = setup({
			forced = function()
				return forced
			end,
		})
		game.currency.add(USER, "Coins", 10000, "Sell")
		local _, uid = game.eggs.purchase(USER, 1, "StudioSwitch")
		T.equal(profile.sim.pets[uid].kind, "SnowyOwl")
		T.equal(game.eggEvents[#game.eggEvents].forced, true)
		forced = "Secret"
		game.clock.advance(5)
		game.eggs.purchase(USER, 1, "StudioSwitch")
		T.equal(game.eggEvents[#game.eggEvents].forced, false, "no Secret pet in Egg 1: normal roll")
	end)

	test("AC2 / AC5: 10,000 openings of Egg 1 through the purchase path stay within 1 pp", function()
		local profile, game = setup({ seed = 20261116 })
		profile.sim.inventorySize = OPENINGS
		game.currency.add(USER, "Coins", OPENINGS * E.Pets.eggPrice(1), "Sell")
		local counts: { [string]: number } = {}
		for _ = 1, OPENINGS do
			game.clock.advance(P.EggsConfig.HatchCooldownSeconds)
			local ok, uid = game.eggs.purchase(USER, 1, "Remote")
			assert(ok, `opening refused: {uid}`)
			local rarity = P.Catalogue.get(profile.sim.pets[uid].kind).rarity
			counts[rarity] = (counts[rarity] or 0) + 1
		end
		local weights: { [string]: number } = {}
		for _, entry in E.Odds.eggOdds(1, false) do
			weights[entry.id] = entry.weight
		end
		local rows = Distribution.assertWithin(counts, weights, OPENINGS, TOLERANCE_PP)
		T.equal(#rows, 5)
		T.equal(petCount(profile), OPENINGS, "every opening added exactly one pet")
		T.equal(game.currency.get(USER, "Coins"), 0, "and spent exactly 240 coins")
	end)
end)

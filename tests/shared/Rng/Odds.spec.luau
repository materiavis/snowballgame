--!strict
-- Concept 7.7, 7.9, 8.5 chance tables and the 10,000-roll check (issue #27 AC3, concept 7.9
-- "Bei 10'000 Test-Öffnungen ... höchstens 1 Prozentpunkt"). Seeded, so every run is the same.

local T = require("../../TestKit")
local Distribution = require("../../helpers/Distribution")
local SeededRandom = require("../../helpers/SeededRandom")
local E = require("../../helpers/Economy")

local Odds = E.Odds
local ROLLS = 10000
local TOLERANCE_PP = 1
local SEED = 20261105

local function weightsOf(entries: { { id: string, weight: number } }): { [string]: number }
	local weights = {}
	for _, entry in entries do
		weights[entry.id] = entry.weight
	end
	return weights
end

local function sum(entries: { { id: string, weight: number } }): number
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end
	return total
end

local function rollMany(roll: () -> string): { [string]: number }
	local counts: { [string]: number } = {}
	for _ = 1, ROLLS do
		local id = roll()
		counts[id] = (counts[id] or 0) + 1
	end
	return counts
end

return T.suite("Rng.Odds (7.7, 7.9, 8.5)", function(test)
	test("egg odds: 60 / 25 / 10 / 4 / 1, adding up to 100 %", function()
		local weights = weightsOf(Odds.eggOdds(1, false))
		T.equal(weights.Common, 60)
		T.equal(weights.Uncommon, 25)
		T.equal(weights.Rare, 10)
		T.equal(weights.Epic, 4)
		T.equal(weights.Legendary, 1)
		T.equal(weights.Secret, nil, "no secret pet in world 1 eggs")
		T.near(sum(Odds.eggOdds(1, false)), 100, 1e-9, "sum")
	end)

	test("luck boost odds: 55 / 25 / 10 / 8 / 2 (Epic and Legendary doubled)", function()
		local normal = weightsOf(Odds.eggOdds(2, false))
		local luck = weightsOf(Odds.eggOdds(2, true))
		T.equal(luck.Common, 55)
		T.equal(luck.Uncommon, 25)
		T.equal(luck.Rare, 10)
		T.equal(luck.Epic, 2 * normal.Epic)
		T.equal(luck.Legendary, 2 * normal.Legendary)
		T.near(sum(Odds.eggOdds(2, true)), 100, 1e-9, "sum")
	end)

	test("eggs from world 2 include the secret pet at 1 in 10,000", function()
		local weights = weightsOf(Odds.eggOdds(3, false))
		T.near(weights.Secret, 0.01, 1e-12, "0.01 %")
		T.near(weights.Common, 60 * (1 - 1 / 10000), 1e-9, "secret taken off in proportion")
		T.near(sum(Odds.eggOdds(3, false)), 100, 1e-9, "sum")
	end)

	test("find odds: zones 6 to 10 of a world have Legendary 1 %, zones 1 to 5 give it to Common (61 %)", function()
		local early = weightsOf(Odds.findOdds(3))
		local late = weightsOf(Odds.findOdds(6))
		local secretShare = 1 - 1 / 2000
		T.near(early.Common, 61 * secretShare, 1e-9, "zone 3 common")
		T.equal(early.Legendary, nil, "zone 3 legendary")
		T.near(late.Common, 60 * secretShare, 1e-9, "zone 6 common")
		T.near(late.Legendary, 1 * secretShare, 1e-9, "zone 6 legendary")
		T.near(late.Secret, 0.05, 1e-12, "yeti footprint 1 in 2,000")
		T.equal(weightsOf(Odds.findOdds(15)).Legendary, nil, "zone 15 = zone 5 of world 2")
		T.isTrue(weightsOf(Odds.findOdds(16)).Legendary ~= nil, "zone 16 = zone 6 of world 2")
		T.near(sum(Odds.findOdds(3)), 100, 1e-9, "sum")
	end)

	test("10,000 seeded egg hatches stay within 1 pp, normal and luck", function()
		for _, luck in { false, true } do
			local generator = SeededRandom.new(SEED)
			local counts = rollMany(function()
				return Odds.rollEgg(1, luck, generator).rarity
			end)
			Distribution.assertWithin(counts, weightsOf(Odds.eggOdds(1, luck)), ROLLS, TOLERANCE_PP)
		end
	end)

	test("10,000 seeded hatches from a world 2 egg stay within 1 pp", function()
		local generator = SeededRandom.new(SEED + 1)
		local counts = rollMany(function()
			return Odds.rollEgg(3, false, generator).rarity
		end)
		Distribution.assertWithin(counts, weightsOf(Odds.eggOdds(3, false)), ROLLS, TOLERANCE_PP)
	end)

	test("10,000 seeded finds stay within 1 pp in zones 1-5 and 6-10", function()
		for _, zone in { 1, 7 } do
			local generator = SeededRandom.new(SEED + zone)
			local counts = rollMany(function()
				return Odds.rollFind(zone, generator)
			end)
			Distribution.assertWithin(counts, weightsOf(Odds.findOdds(zone)), ROLLS, TOLERANCE_PP)
			T.equal(if zone == 1 then counts.Legendary else nil, nil, "no Legendary find in zone 1")
		end
	end)

	test("Frosty at 1 in 50 per hatch stays within 1 pp over 10,000 hatches", function()
		local generator = SeededRandom.new(SEED + 50)
		local counts = rollMany(function()
			return if Odds.rollEgg(1, false, generator).frosty then "Frosty" else "Normal"
		end)
		Distribution.assertWithin(counts, { Frosty = 2, Normal = 98 }, ROLLS, TOLERANCE_PP)
	end)

	test("the same seed gives the same hatches", function()
		local first, second = SeededRandom.new(SEED), SeededRandom.new(SEED)
		for i = 1, 200 do
			local a, b = Odds.rollEgg(2, false, first), Odds.rollEgg(2, false, second)
			T.equal(a.rarity, b.rarity, `hatch {i}`)
			T.equal(a.frosty, b.frosty, `frosty {i}`)
		end
	end)

	test("Weighted.pick: bounds, zero weights and broken tables", function()
		local entries = { { id = "A", weight = 1 }, { id = "B", weight = 0 }, { id = "C", weight = 3 } }
		T.equal(E.Weighted.pick(entries, 0), "A")
		T.equal(E.Weighted.pick(entries, 0.2499), "A")
		T.equal(E.Weighted.pick(entries, 0.25), "C", "a zero weight is never picked")
		T.equal(E.Weighted.pick(entries, 0.9999999), "C")
		T.throws(function()
			E.Weighted.pick(entries, 1)
		end, "roll must be")
		T.throws(function()
			E.Weighted.pick({}, 0.5)
		end, "empty")
		T.throws(function()
			E.Weighted.pick({ { id = "A", weight = 0 / 0 } }, 0.5)
		end, "finite")
		T.throws(function()
			Odds.eggOdds(11, false)
		end, "egg must be")
		T.throws(function()
			Odds.findOdds(0)
		end, "unknown zone")
	end)
end)

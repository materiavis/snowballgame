--!strict
-- Example: seeded distribution test (concept 4.4: 10,000 openings, at most 1 pp off).
-- The weights below are fixture values for the test, not real egg or find odds.

local T = require("../TestKit")
local Distribution = require("../helpers/Distribution")
local SeededRandom = require("../helpers/SeededRandom")
local ExampleWeightedPick = require("./fixtures/ExampleWeightedPick")

local ROLLS = 10000
local TOLERANCE_PP = 1
-- Any fixed seed works; fixing it makes the run identical on every machine and in CI.
local SEED = 20261104

local FIXTURE_ENTRIES: { ExampleWeightedPick.Entry } = {
	{ id = "Common", weight = 50 },
	{ id = "Uncommon", weight = 30 },
	{ id = "Rare", weight = 15 },
	{ id = "Epic", weight = 5 },
}

local function weightsOf(entries: { ExampleWeightedPick.Entry }): { [string]: number }
	local weights = {}
	for _, entry in entries do
		weights[entry.id] = entry.weight
	end
	return weights
end

return T.suite("Example RNG (seeded weighted pick)", function(test)
	test("10,000 seeded rolls stay within 1 pp of every chance", function()
		local rng = SeededRandom.new(SEED)
		local counts: { [string]: number } = {}
		for _ = 1, ROLLS do
			local id = ExampleWeightedPick.pick(FIXTURE_ENTRIES, rng.next())
			counts[id] = (counts[id] or 0) + 1
		end
		Distribution.assertWithin(counts, weightsOf(FIXTURE_ENTRIES), ROLLS, TOLERANCE_PP)
	end)

	test("the same seed gives the same sequence", function()
		local first, second = SeededRandom.new(SEED), SeededRandom.new(SEED)
		for i = 1, 100 do
			T.equal(first.next(), second.next(), `roll {i}`)
		end
	end)

	test("roll bounds map to the first and last entry", function()
		T.equal(ExampleWeightedPick.pick(FIXTURE_ENTRIES, 0), "Common")
		T.equal(ExampleWeightedPick.pick(FIXTURE_ENTRIES, 0.999999), "Epic")
	end)

	-- Guards against a check that can never fail: a skew just over the limit must be caught.
	test("the distribution check rejects a 1.1 pp skew and a lost roll", function()
		local weights = { Heads = 1, Tails = 1 }
		T.throws(function()
			Distribution.assertWithin({ Heads = 5110, Tails = 4890 }, weights, ROLLS, TOLERANCE_PP)
		end, "Heads observed 51.10%%")
		T.throws(function()
			Distribution.assertWithin({ Heads = 5000, Tails = 4999 }, weights, ROLLS, TOLERANCE_PP)
		end, "add up to 9999")
		T.throws(function()
			Distribution.assertWithin({ Heads = 5000, Edge = 5000 }, weights, ROLLS, TOLERANCE_PP)
		end, "Edge was rolled but has no weight")
	end)
end)

--!strict
-- #40 AC7 (ADR 0003 "RNG distribution, 10,000 rolls per egg and find table, ±1 pp"): 10,000
-- seeded finds per table through FindService's own roll and spawn path, compared with the
-- concept 7.7 percentages typed in by hand. Zones 1-5 of a world: Common 61, Uncommon 25,
-- Rare 10, Epic 4, no Legendary. Zones 6-10: 60 / 25 / 10 / 4 / 1. Plus the secret find at
-- 1 in 2,000 per spawned find, taken off every rarity in proportion.

local T = require("../../../TestKit")
local Distribution = require("../../../helpers/Distribution")
local FindWorld = require("./FindWorld")

local USER = FindWorld.USER
local ROLLS = 10000
local TOLERANCE_PP = 1
local SECRET_SHARE = 1 - 1 / 2000

local EARLY = { Common = 61, Uncommon = 25, Rare = 10, Epic = 4 }
local LATE = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1 }

-- The concept table with the secret find's 0.05 % taken off in proportion.
local function withSecret(table7: { [string]: number }): { [string]: number }
	local weights: { [string]: number } = {}
	for rarity, chance in table7 do
		weights[rarity] = chance * SECRET_SHARE
	end
	weights.Secret = 100 / 2000
	return weights
end

-- 10,000 finds spawned at one point of `zone`, counted by rarity and by find id.
local function spawnMany(zone: number, seed: number): ({ [string]: number }, { [string]: number })
	local w = FindWorld.new({ seed = seed })
	w.core.addPoint("P", zone, 0, 0, 0, "P")
	w.core.activate(USER)
	local byRarity: { [string]: number } = {}
	local byId: { [string]: number } = {}
	w.core.subscribe(function(event: any)
		if event.kind == "Spawn" then
			byRarity[event.rarity] = (byRarity[event.rarity] or 0) + 1
			byId[event.findId] = (byId[event.findId] or 0) + 1
		end
	end)
	for _ = 1, ROLLS do
		w.core.spawnNow(USER)
	end
	return byRarity, byId
end

return T.suite("FindService rolls: 10,000 per table (AC7)", function(test)
	test("zones 1-5 table: 10,000 spawns within 1 pp of 61 / 25 / 10 / 4, never Legendary", function()
		for _, zone in { 1, 5 } do
			local counts, ids = spawnMany(zone, 7001 + zone)
			Distribution.assertWithin(counts, withSecret(EARLY), ROLLS, TOLERANCE_PP)
			T.equal(counts.Legendary, nil, `no Legendary in zone {zone}`)
			T.equal(ids.GoldenCowbell, nil)
			T.equal(ids.PineCone, counts.Common, "every Common is a Pine Cone (Alps)")
			T.equal(ids.RockCrystal, counts.Epic, "every Epic is a Rock Crystal")
		end
	end)

	test("zones 6-10 table: 10,000 spawns within 1 pp of 60 / 25 / 10 / 4 / 1", function()
		for _, zone in { 6, 10 } do
			local counts, ids = spawnMany(zone, 7001 + zone)
			Distribution.assertWithin(counts, withSecret(LATE), ROLLS, TOLERANCE_PP)
			T.isTrue((counts.Legendary or 0) > 0, `Legendary appears in zone {zone}`)
			T.equal(ids.GoldenCowbell, counts.Legendary, "every Legendary is a Golden Cowbell")
		end
	end)

	test("the tables FindService rolls are exactly the concept tables", function()
		local w = FindWorld.new()
		for zone, table7 in { [3] = EARLY, [8] = LATE } do
			local weights: { [string]: number } = {}
			for _, entry in FindWorld.E.Odds.findOdds(zone) do
				weights[entry.id] = entry.weight
			end
			for rarity, weight in withSecret(table7) do
				T.near(weights[rarity], weight, 1e-9, `zone {zone} {rarity}`)
			end
			if zone < 6 then
				T.equal(weights.Legendary, nil)
			end
		end
		T.equal(w.core.findFor(15, "Legendary"), nil, "zone 15 (world 2) has no Alps finds")
	end)

	test("secret find: 1 in 2,000 per spawned find over 200,000 spawns (within 0.02 pp)", function()
		local w = FindWorld.new({ seed = 2000 })
		local secret = 0
		local total = 200000
		for index = 1, total do
			local rarity = w.core.roll(USER, if index % 2 == 0 then 2 else 7)
			if rarity == "Secret" then
				secret += 1
			end
		end
		T.near(secret / total * 100, 0.05, 0.02, `secret share {secret / total * 100} %`)
	end)

	test("the same seed gives the same finds", function()
		local first = FindWorld.new({ seed = 99 })
		local second = FindWorld.new({ seed = 99 })
		for _ = 1, 500 do
			T.equal(first.core.roll(USER, 6), second.core.roll(USER, 6))
		end
	end)
end)

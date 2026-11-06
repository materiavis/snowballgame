--!strict
-- Structural checks for the chapter 7 to 9 config modules (issue #27 AC6): they load, are
-- frozen all the way down, keep the ✅ knobs at the concept values and the currency paths
-- point at real number fields of the schema v1 profile.

local T = require("../TestKit")
local DataConfig = require("../../src/shared/Config/Data")
local Schema = require("../../src/server/Services/DataService/Schema")

local MODULES = {
	"Ball",
	"Currency",
	"Display",
	"Economy",
	"Events",
	"Fight",
	"Finds",
	"Lobby",
	"Monetization",
	"Pets",
	"Rarity",
	"Social",
	"Upgrades",
	"Zones",
}

local function load(name: string): any
	return (require :: any)(`../../src/shared/Config/{name}`)
end

local function assertDeepFrozen(value: any, path: string)
	if type(value) ~= "table" then
		return
	end
	T.isTrue(table.isfrozen(value), `{path} is frozen`)
	for key, inner in value do
		assertDeepFrozen(inner, `{path}.{tostring(key)}`)
	end
end

local function at(profile: any, path: { string }): any
	local node = profile
	for _, key in path do
		node = node[key]
	end
	return node
end

return T.suite("src/shared/Config economy modules", function(test)
	test("every module loads and is frozen all the way down", function()
		for _, name in MODULES do
			assertDeepFrozen(load(name), name)
		end
	end)

	test("7.6 knobs (✅, game design only): 1.25, 1.2 and 2 + 2n", function()
		local Zones = load("Zones")
		T.equal(Zones.SizeGrowth, 1.25)
		T.equal(Zones.StrengthGrowth, 1.2)
		T.equal(Zones.BallsPerBarrierBase, 2)
		T.equal(Zones.BallsPerBarrierPerZone, 2)
		T.equal(Zones.MaxSizeBase, 2)
		T.equal(Zones.BallValueFactor, 10)
	end)

	test("odds tables add up to 100 %", function()
		for label, odds in { eggs = load("Pets").Odds, luck = load("Pets").LuckOdds, finds = load("Finds").Odds } do
			local total = 0
			for _, chance in odds do
				total += chance
			end
			T.equal(total, 100, label)
		end
	end)

	test("8.1: Coins and Snow Coins are separate profile fields; no Robux item grants either", function()
		local Currency = load("Currency")
		local profile = Schema.new(DataConfig).newProfile()
		local seen = {}
		for id, currency in Currency.Currencies do
			T.equal(type(at(profile, currency.Path)), "number", `{id} path`)
			if currency.TotalPath then
				T.equal(type(at(profile, currency.TotalPath)), "number", `{id} total path`)
			end
			local key = table.concat(currency.Path, ".")
			T.equal(seen[key], nil, `{id} shares a balance`)
			seen[key] = true
			T.isTrue(currency.MaxChange > 0 and currency.MaxBalance >= currency.MaxChange, `{id} bounds`)
		end
		T.isTrue(Currency.Currencies.Coins ~= nil and Currency.Currencies.SnowCoins ~= nil)
		-- Robux items are game passes, developer products and private servers; none is a
		-- currency grant (9.5). Coin items are multipliers only, named in Economy bonus tables.
		local Monetization = load("Monetization")
		for _, group in { Monetization.Gamepasses, Monetization.DeveloperProducts } do
			for id in group do
				T.equal(Currency.Currencies[id], nil, `{id} is not a currency`)
			end
		end
	end)

	test("Robux items carry a price and a placeholder asset id", function()
		local Monetization = load("Monetization")
		for _, group in { Monetization.Gamepasses, Monetization.DeveloperProducts } do
			for id, item in group do
				T.isTrue(item.Robux > 0 and item.Robux % 1 == 0, `{id} price`)
				T.equal(item.AssetId, 0, `{id} id is filled in by humans at publish`)
			end
		end
	end)

	test("upgrade ids match the save format", function()
		local Upgrades = load("Upgrades")
		local saved = Schema.new(DataConfig).newProfile().sim.upgrades
		for _, id in Upgrades.Order do
			T.isTrue(Upgrades.Definitions[id] ~= nil, `{id} defined`)
			T.equal(saved[id], 0, `{id} saved`)
		end
	end)
end)

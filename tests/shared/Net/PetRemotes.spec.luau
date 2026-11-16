--!strict
-- #41 AC8: the EggHatch and PetEquip declarations. EggHatch takes no argument at all (the server
-- finds the station); PetEquip takes a bounded uid string and a boolean. Both are rate limited.

local T = require("../../TestKit")
local FakeClock = require("../../helpers/FakeClock")
local Schema = require("../../../src/shared/Net/Schema")
local Registry = require("../../../src/shared/Net/Registry")
local RateLimiter = require("../../../src/shared/Net/RateLimiter")
local Stats = require("../../../src/shared/Net/Stats")
local Guard = require("../../../src/shared/Net/Guard")
local declareRemotes = require("../../../src/shared/Net/Remotes")
local NetConfig = require("../../../src/shared/Config/Net")
local UpgradesConfig = require("../../../src/shared/Config/Upgrades")

local PLAYER = { Name = "Tester" }

local function harness(name: string)
	local definition = Registry.build(declareRemotes(Schema, NetConfig, UpgradesConfig))[name]
	local stats = Stats.new()
	local handled = {}
	local guarded = Guard.new(definition, {
		limiter = RateLimiter.new(definition.rateLimit, FakeClock.new().now),
		stats = stats,
		getHandler = function()
			return function(_player: any, ...: any)
				table.insert(handled, table.pack(...))
			end
		end,
		reportError = function() end,
	})
	return function(...: any)
		guarded(PLAYER, ...)
	end, handled, stats
end

return T.suite("EggHatch and PetEquip remotes (ADR 0013)", function(test)
	test("EggHatch: no arguments; an egg number, price or rarity from the client is refused", function()
		local call, handled, stats = harness("EggHatch")
		call()
		T.equal(#handled, 1)
		for _, args in { table.pack(1), table.pack(240), table.pack("Legendary") } do
			call(table.unpack(args, 1, args.n))
		end
		T.equal(#handled, 1)
		T.equal(stats:get("EggHatch").byReason.Arity, 2, "two more within the burst, both refused for arity")
		T.equal(stats:get("EggHatch").byReason.Rate, 1, "the burst of 3 is spent")
	end)

	test("PetEquip: a bounded uid and a boolean, nothing else", function()
		local call, handled, stats = harness("PetEquip")
		call("1001_6553f100_0001", true)
		T.equal(#handled, 1)
		T.equal(handled[1][1], "1001_6553f100_0001")
		T.equal(handled[1][2], true)
		local bad = {
			table.pack(string.rep("x", NetConfig.Pets.MaxUidLength + 1), true),
			table.pack("", true),
			table.pack(42, true),
			table.pack("uid", "true"),
			table.pack("uid"),
			table.pack("uid", true, 5),
		}
		for _, args in bad do
			call(table.unpack(args, 1, args.n))
		end
		T.equal(#handled, 1, "the handler never sees a malformed call")
		local counts = stats:get("PetEquip")
		T.equal(counts.rejected, #bad)
	end)
end)

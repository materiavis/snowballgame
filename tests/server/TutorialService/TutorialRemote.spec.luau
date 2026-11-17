--!strict
-- The TutorialHintDone remote through the Net guard (#42 AC6, CLAUDE.md §6): one argument, one
-- of Config.Tutorial.ClientReportable; anything else is dropped before a handler runs; spam is
-- rate limited. What the handler then accepts (only a showing hint) is TutorialCore.checkReport.

local T = require("../../TestKit")
local FakeClock = require("../../helpers/FakeClock")
local Guard = require("../../../src/shared/Net/Guard")
local NetConfig = require("../../../src/shared/Config/Net")
local RateLimiter = require("../../../src/shared/Net/RateLimiter")
local Registry = require("../../../src/shared/Net/Registry")
local Schema = require("../../../src/shared/Net/Schema")
local Stats = require("../../../src/shared/Net/Stats")
local declareRemotes = require("../../../src/shared/Net/Remotes")
local TutorialConfig = require("../../../src/shared/Config/Tutorial")
local UpgradesConfig = require("../../../src/shared/Config/Upgrades")

local NAME = "TutorialHintDone"
local PLAYER = { Name = "Tester" }

local function guarded(handler: any)
	local definition = Registry.build(declareRemotes(Schema, NetConfig, UpgradesConfig, TutorialConfig))[NAME]
	local clock = FakeClock.new()
	local stats = Stats.new()
	local call = Guard.new(definition, {
		limiter = RateLimiter.new(definition.rateLimit, clock.now),
		stats = stats,
		getHandler = function()
			return handler
		end,
		reportError = function() end,
	})
	return call, stats, clock, definition
end

return T.suite("TutorialHintDone remote", function(test)
	test("declared as a client -> server event with its own rate limit", function()
		local _, _, _, definition = guarded(nil)
		T.equal(definition.kind, "Event")
		T.equal(definition.rateLimit, NetConfig.RateLimits.TutorialHintDone)
	end)

	test("a reportable id reaches the handler with that id", function()
		local got = {}
		local call = guarded(function(_player, id)
			table.insert(got, id)
		end)
		call(PLAYER, "UpgradesButton")
		T.equal(table.concat(got, ","), "UpgradesButton")
	end)

	test("other ids, other types and extra arguments are dropped before the handler", function()
		local handled = 0
		for _, args in
			{
				table.pack("ZoneMove"),
				table.pack("MaxScale"),
				table.pack("NoSuchHint"),
				table.pack(""),
				table.pack(1),
				table.pack({ "UpgradesButton" }),
				table.pack(nil),
				{ n = 0 },
				table.pack("UpgradesButton", true),
			}
		do
			local call, stats = guarded(function()
				handled += 1
			end)
			call(PLAYER, table.unpack(args, 1, args.n))
			T.equal(stats:get(NAME).accepted, 0, `{args.n} args, {tostring(args[1])} dropped`)
		end
		T.equal(handled, 0)
	end)

	test("spam is rate limited per player", function()
		local handled = 0
		local call, stats = guarded(function()
			handled += 1
		end)
		local limit = NetConfig.RateLimits.TutorialHintDone
		for _ = 1, limit.Burst + 5 do
			call(PLAYER, "UpgradesButton")
		end
		T.equal(handled, limit.Burst)
		T.equal(stats:get(NAME).byReason.Rate, 5)
	end)
end)

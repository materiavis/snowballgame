--!strict
-- The travel remotes through the Net guard (issue #28 AC4, CLAUDE.md §6): the Lobby button
-- request takes no arguments, so anything a client adds is dropped; spam is rate limited; the
-- server -> client notice has no handler, so a client firing it reaches nothing.

local T = require("../../TestKit")
local FakeClock = require("../../helpers/FakeClock")
local Guard = require("../../../src/shared/Net/Guard")
local NetConfig = require("../../../src/shared/Config/Net")
local RateLimiter = require("../../../src/shared/Net/RateLimiter")
local Registry = require("../../../src/shared/Net/Registry")
local Schema = require("../../../src/shared/Net/Schema")
local Stats = require("../../../src/shared/Net/Stats")
local declareRemotes = require("../../../src/shared/Net/Remotes")

local PLAYER = { Name = "Tester" }

local function guarded(name: string, handler: any)
	local definition = Registry.build(declareRemotes(Schema, NetConfig))[name]
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

return T.suite("Travel remotes", function(test)
	test("TravelRequestLobby: no arguments accepted, extra arguments dropped", function()
		local handled = 0
		local call, stats = guarded("TravelRequestLobby", function()
			handled += 1
		end)
		call(PLAYER)
		T.equal(handled, 1)
		T.equal(stats:get("TravelRequestLobby").accepted, 1)
		for _, args in { table.pack("Lobby"), table.pack(12345), table.pack({ placeId = 1 }), table.pack(nil, 1) } do
			-- A fresh guard per case keeps the rate limit out of the way.
			local fresh, freshStats = guarded("TravelRequestLobby", function()
				handled += 1
			end)
			fresh(PLAYER, table.unpack(args, 1, args.n))
			T.equal(freshStats:get("TravelRequestLobby").byReason.Arity, 1, `{args.n} args dropped as Arity`)
		end
		T.equal(handled, 1, "a client cannot pass a destination")
	end)

	test("TravelRequestLobby: spam is rate limited per player", function()
		local handled = 0
		local call, stats, clock = guarded("TravelRequestLobby", function()
			handled += 1
		end)
		local limit = NetConfig.RateLimits.TravelRequestLobby
		for _ = 1, limit.Burst + 5 do
			call(PLAYER)
		end
		T.equal(handled, limit.Burst)
		T.equal(stats:get("TravelRequestLobby").byReason.Rate, 5)
		clock.advance(1 / limit.RefillPerSecond)
		call(PLAYER)
		T.equal(handled, limit.Burst + 1)
	end)

	test("TravelNotice is server -> client only: a client call reaches no handler", function()
		local call, stats, _, definition = guarded("TravelNotice", nil)
		T.equal(#definition.args, 0)
		call(PLAYER)
		T.equal(stats:get("TravelNotice").byReason.NoHandler, 1)
	end)
end)

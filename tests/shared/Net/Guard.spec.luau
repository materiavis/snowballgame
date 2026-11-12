--!strict
-- AC1 for #24: malformed, out-of-range, over-rate and unauthorised calls are dropped and
-- counted, the handler never sees them, and nothing throws. Runs a test-only declaration
-- (the old NetExample remote, removed with #28); the clock is faked, players are plain tables.

local T = require("../../TestKit")
local FakeClock = require("../../helpers/FakeClock")
local Schema = require("../../../src/shared/Net/Schema")
local Registry = require("../../../src/shared/Net/Registry")
local RateLimiter = require("../../../src/shared/Net/RateLimiter")
local Stats = require("../../../src/shared/Net/Stats")
local Guard = require("../../../src/shared/Net/Guard")

local NAN = 0 / 0
local INF = math.huge

type Harness = {
	call: (player: any, ...any) -> { n: number, [number]: any },
	stats: Stats.Stats,
	clock: FakeClock.FakeClock,
	handled: { { any } },
	errors: { string },
}

local function harness(definition: any, handler: Guard.Handler?): Harness
	local clock = FakeClock.new()
	local stats = Stats.new()
	local handled: { { any } } = {}
	local errors: { string } = {}
	local guarded = Guard.new(definition, {
		limiter = RateLimiter.new(definition.rateLimit, clock.now),
		stats = stats,
		getHandler = function()
			return handler or function(player: any, ...: any)
				table.insert(handled, { player, ... })
			end
		end,
		reportError = function(_name: string, message: string)
			table.insert(errors, message)
		end,
	})
	-- Every call goes through pcall: a guard that throws fails the test right here.
	local function call(player: any, ...: any)
		local results = table.pack(pcall(guarded, player, ...))
		if not results[1] then
			error(`guard threw: {results[2]}`, 2)
		end
		return table.pack(table.unpack(results, 2, results.n))
	end
	return { call = call, stats = stats, clock = clock, handled = handled, errors = errors }
end

-- Test fixture, not a design value: a whole number 1..MaxAmount and a list of up to
-- MaxValues bounded numbers.
local example = { MaxAmount = 10, MaxValues = 3, MaxValueMagnitude = 1000 }
local exampleLimit = { Burst = 5, RefillPerSecond = 2 }
local exampleBurst = exampleLimit.Burst

local function exampleDefinition()
	return Registry.build({
		NetExample = {
			kind = "Event",
			args = {
				Schema.number({ min = 1, max = example.MaxAmount, integer = true }),
				Schema.array(
					Schema.number({ min = -example.MaxValueMagnitude, max = example.MaxValueMagnitude }),
					{ maxLength = example.MaxValues }
				),
			},
			rateLimit = exampleLimit,
		},
	}).NetExample
end

local PLAYER = { Name = "Tester" }
local OTHER = { Name = "Other" }

return T.suite("src/shared/Net/Guard", function(test)
	test("a valid call reaches the handler with its arguments", function()
		local h = harness(exampleDefinition())
		h.call(PLAYER, 1, { 0.5, -2 })
		T.equal(#h.handled, 1)
		T.equal(h.handled[1][1], PLAYER, "handler gets the calling player first")
		T.equal(h.handled[1][2], 1)
		T.equal(h.stats:get("NetExample").accepted, 1)
		T.equal(h.stats:get("NetExample").rejected, 0)
	end)

	test("malformed calls are dropped, counted and never throw", function()
		local cases: { { label: string, reason: string, args: { n: number, [number]: any } } } = {
			{ label = "wrong type", reason = "Args", args = table.pack("1", {}) },
			{ label = "table instead of number", reason = "Args", args = table.pack({}, {}) },
			{ label = "too few args", reason = "Arity", args = table.pack(1) },
			{ label = "no args", reason = "Arity", args = { n = 0 } },
			{ label = "too many args", reason = "Arity", args = table.pack(1, {}, "extra") },
			{ label = "nil in a required slot", reason = "Args", args = table.pack(nil, {}) },
			{ label = "NaN", reason = "Args", args = table.pack(NAN, {}) },
			{ label = "inf", reason = "Args", args = table.pack(INF, {}) },
			{ label = "fractional count", reason = "Args", args = table.pack(1.5, {}) },
			{ label = "wrong-typed table contents", reason = "Args", args = table.pack(1, { "x" }) },
			{ label = "NaN inside the table", reason = "Args", args = table.pack(1, { NAN }) },
			{ label = "table with a string key", reason = "Args", args = table.pack(1, { a = 1 }) },
			{ label = "not a table", reason = "Args", args = table.pack(1, 5) },
		}
		for _, case in cases do
			-- A fresh harness per case keeps the rate limit out of the way.
			local h = harness(exampleDefinition())
			h.call(PLAYER, table.unpack(case.args, 1, case.args.n))
			local counts = h.stats:get("NetExample")
			T.equal(#h.handled, 0, `{case.label}: handler must not run`)
			T.equal(counts.rejected, 1, `{case.label}: counted`)
			T.equal(counts.byReason[case.reason], 1, `{case.label}: reason {case.reason}`)
		end
	end)

	test("out-of-range calls are dropped and counted", function()
		local cases = {
			{ label = "count below min", args = table.pack(0, {}) },
			{ label = "count above max", args = table.pack(example.MaxAmount + 1, {}) },
			{ label = "value above max", args = table.pack(1, { example.MaxValueMagnitude + 1 }) },
			{ label = "value below min", args = table.pack(1, { -example.MaxValueMagnitude - 1 }) },
			{ label = "too many values", args = table.pack(1, table.create(example.MaxValues + 1, 0)) },
		}
		for _, case in cases do
			local h = harness(exampleDefinition())
			h.call(PLAYER, table.unpack(case.args, 1, case.args.n))
			T.equal(#h.handled, 0, `{case.label}: handler must not run`)
			T.equal(h.stats:get("NetExample").byReason.Args, 1, `{case.label}: counted as Args`)
		end
		local h = harness(exampleDefinition())
		h.call(PLAYER, example.MaxAmount, table.create(example.MaxValues, example.MaxValueMagnitude))
		T.equal(#h.handled, 1, "the bounds themselves are allowed")
	end)

	test("over-rate calls are dropped and counted per player, and allowed again after refill", function()
		local h = harness(exampleDefinition())
		for _ = 1, exampleBurst + 3 do
			h.call(PLAYER, 1, {})
		end
		local counts = h.stats:get("NetExample")
		T.equal(#h.handled, exampleBurst, "only the burst reaches the handler")
		T.equal(counts.byReason.Rate, 3, "the rest are counted as Rate")

		h.call(OTHER, 1, {})
		T.equal(#h.handled, exampleBurst + 1, "another player has their own budget")

		h.clock.advance(1 / exampleLimit.RefillPerSecond)
		h.call(PLAYER, 1, {})
		T.equal(#h.handled, exampleBurst + 2, "one token back after one refill interval")
	end)

	test("malformed calls also spend rate budget, so floods stay capped", function()
		local h = harness(exampleDefinition())
		for _ = 1, exampleBurst do
			h.call(PLAYER, "junk")
		end
		h.call(PLAYER, 1, {})
		T.equal(#h.handled, 0)
		T.equal(h.stats:get("NetExample").byReason.Rate, 1)
	end)

	test("the authorize hook can drop a call, and an erroring hook drops it too", function()
		local owned = { Owner = PLAYER }
		local definitions = Registry.build({
			Claim = {
				kind = "Event",
				args = { Schema.struct({ Owner = Schema.struct({ Name = Schema.string({ maxLength = 16 }) }) }) },
				rateLimit = { Burst = 10, RefillPerSecond = 1 },
				authorize = function(player: any, thing: any)
					if thing.Owner.Name == "boom" then
						error("hook bug")
					end
					return thing.Owner.Name == player.Name, "not the owner"
				end,
			},
		})
		local h = harness(definitions.Claim)
		h.call(PLAYER, owned)
		h.call(OTHER, owned)
		h.call(PLAYER, { Owner = { Name = "boom" } })
		local counts = h.stats:get("Claim")
		T.equal(#h.handled, 1, "only the owner gets through")
		T.equal(counts.byReason.Auth, 2, "not-owner and hook error are counted as Auth")
	end)

	test("a handler error is caught, counted and reported on the server only", function()
		local h = harness(exampleDefinition(), function()
			error("handler bug")
		end)
		h.call(PLAYER, 1, {})
		local counts = h.stats:get("NetExample")
		T.equal(counts.handlerErrors, 1)
		T.equal(counts.accepted, 0)
		T.equal(#h.errors, 1)
		T.isTrue(string.find(h.errors[1], "handler bug", 1, true) ~= nil)
	end)

	test("a call without a registered handler is dropped and counted", function()
		local stats = Stats.new()
		local definition = exampleDefinition()
		local guarded = Guard.new(definition, {
			limiter = RateLimiter.new(definition.rateLimit, FakeClock.new().now),
			stats = stats,
			getHandler = function()
				return nil
			end,
			reportError = function() end,
		})
		T.isTrue(pcall(guarded, PLAYER, 1, {}))
		T.equal(stats:get("NetExample").byReason.NoHandler, 1)
	end)

	test("a Function remote returns handler values, and nothing when rejected", function()
		local definitions = Registry.build({
			Echo = {
				kind = "Function",
				args = { Schema.number({ min = 0, max = 5 }) },
				rateLimit = { Burst = 10, RefillPerSecond = 1 },
			},
		})
		local h = harness(definitions.Echo, function(_player: any, value: number)
			return value * 2, "ok"
		end)
		local accepted = h.call(PLAYER, 2)
		T.equal(accepted.n, 2)
		T.equal(accepted[1], 4)
		T.equal(accepted[2], "ok")
		local rejected = h.call(PLAYER, 99)
		T.equal(rejected.n, 0, "a rejected invoke returns no values (nil to the client)")
	end)

	test("a subscriber that errors does not break the call", function()
		local h = harness(exampleDefinition())
		local seen: { string } = {}
		h.stats:subscribe(function()
			error("listener bug")
		end)
		h.stats:subscribe(function(event)
			table.insert(seen, event.outcome)
		end)
		h.call(PLAYER, "bad", {})
		h.call(PLAYER, 1, {})
		T.equal(seen[1], "Rejected")
		T.equal(seen[2], "Accepted")
		T.equal(h.stats:totalRejected(), 1)
	end)
end)

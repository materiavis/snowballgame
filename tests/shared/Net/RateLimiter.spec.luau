--!strict
-- Token bucket behaviour with an injected clock. The limits here are test values.

local T = require("../../TestKit")
local FakeClock = require("../../helpers/FakeClock")
local RateLimiter = require("../../../src/shared/Net/RateLimiter")

local LIMIT = { Burst = 3, RefillPerSecond = 2 }

local function takeMany(limiter: RateLimiter.RateLimiter, key: any, times: number): number
	local allowed = 0
	for _ = 1, times do
		if limiter:take(key) then
			allowed += 1
		end
	end
	return allowed
end

return T.suite("src/shared/Net/RateLimiter", function(test)
	test("allows the burst, then refuses until tokens refill", function()
		local clock = FakeClock.new()
		local limiter = RateLimiter.new(LIMIT, clock.now)
		T.equal(takeMany(limiter, "a", 10), 3, "burst")
		clock.advance(0.49)
		T.equal(limiter:take("a"), false, "under one token after 0.49 s")
		clock.advance(0.01)
		T.equal(limiter:take("a"), true, "one token after 0.5 s")
		T.equal(limiter:take("a"), false, "and only one")
	end)

	test("refill never exceeds the burst", function()
		local clock = FakeClock.new()
		local limiter = RateLimiter.new(LIMIT, clock.now)
		takeMany(limiter, "a", 3)
		clock.advance(3600)
		T.equal(takeMany(limiter, "a", 10), 3)
	end)

	test("keys are independent", function()
		local clock = FakeClock.new()
		local limiter = RateLimiter.new(LIMIT, clock.now)
		takeMany(limiter, "a", 3)
		T.equal(limiter:take("a"), false)
		T.equal(limiter:take("b"), true, "another player is unaffected")
	end)

	test("a clock that steps backwards mints no tokens", function()
		local clock = FakeClock.new(100)
		local limiter = RateLimiter.new(LIMIT, clock.now)
		takeMany(limiter, "a", 3)
		clock.set(0)
		T.equal(limiter:take("a"), false)
	end)

	test("forget drops a key's bucket", function()
		local clock = FakeClock.new()
		local limiter = RateLimiter.new(LIMIT, clock.now)
		takeMany(limiter, "a", 3)
		limiter:forget("a")
		T.equal(limiter._buckets["a"], nil)
		T.equal(limiter:take("a"), true, "a returning key starts with a full bucket")
	end)
end)

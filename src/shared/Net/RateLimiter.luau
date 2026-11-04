--!strict
-- Per-key token bucket. Pure: the clock is passed in, so tests drive time by hand and the
-- server passes os.clock.
--
-- A bucket allows a short burst (e.g. a double click) and then a steady rate, which fits
-- intents like throws or purchases better than a fixed window that resets all at once.

export type Limit = { Burst: number, RefillPerSecond: number }
export type Clock = () -> number

type Bucket = { tokens: number, updatedAt: number }

export type RateLimiter = {
	take: (self: RateLimiter, key: any) -> boolean,
	forget: (self: RateLimiter, key: any) -> (),
	_burst: number,
	_refill: number,
	_clock: Clock,
	_buckets: { [any]: Bucket },
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- The limit is checked once by Registry.build at startup, where a bad value fails loudly.
function RateLimiter.new(limit: Limit, clock: Clock): RateLimiter
	local self = {
		_burst = limit.Burst,
		_refill = limit.RefillPerSecond,
		_clock = clock,
		_buckets = {},
	}
	return (setmetatable(self, RateLimiter) :: any) :: RateLimiter
end

-- Returns true and spends one token if the key may act now.
function RateLimiter.take(self: RateLimiter, key: any): boolean
	local now = self._clock()
	local bucket = self._buckets[key]
	if bucket == nil then
		bucket = { tokens = self._burst, updatedAt = now }
		self._buckets[key] = bucket
	else
		-- A clock that steps backwards must not mint tokens.
		local elapsed = math.max(0, now - bucket.updatedAt)
		bucket.tokens = math.min(self._burst, bucket.tokens + elapsed * self._refill)
		bucket.updatedAt = now
	end
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

-- Called when a player leaves, so buckets do not pile up over a long server life.
function RateLimiter.forget(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return table.freeze(RateLimiter)

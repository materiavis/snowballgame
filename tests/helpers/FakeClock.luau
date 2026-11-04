--!strict
-- Hand-driven clock for anything that takes a `() -> number` clock (e.g. Net.RateLimiter),
-- so time-based tests never sleep and give the same result on every run.

export type FakeClock = {
	now: () -> number,
	advance: (seconds: number) -> (),
	set: (seconds: number) -> (),
}

local FakeClock = {}

function FakeClock.new(start: number?): FakeClock
	local current = start or 0
	return {
		now = function()
			return current
		end,
		advance = function(seconds: number)
			current += seconds
		end,
		set = function(seconds: number)
			current = seconds
		end,
	}
end

return table.freeze(FakeClock)

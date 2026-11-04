--!strict
-- Per-remote rate limits and argument bounds for src/shared/Net.
-- Every remote declared in Net/Remotes takes its limit from RateLimits by its own name, so a
-- new remote without an entry here fails at startup instead of running unlimited.
--
-- Burst: calls a player may make at once. RefillPerSecond: steady calls per second after that.

local Net = {
	RateLimits = table.freeze({
		-- EXAMPLE ONLY (see Net/Remotes). Not a design value.
		NetExample = table.freeze({ Burst = 5, RefillPerSecond = 2 }),
	}),

	-- EXAMPLE ONLY. Bounds for the example remote's arguments. Not design values.
	Example = table.freeze({
		MaxAmount = 10,
		MaxValues = 3,
		MaxValueMagnitude = 1000,
	}),
}

return table.freeze(Net)

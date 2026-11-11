--!strict
-- Per-remote rate limits for src/shared/Net.
-- Every remote declared in Net/Remotes takes its limit from RateLimits by its own name, so a
-- new remote without an entry here fails at startup instead of running unlimited.
--
-- Burst: calls a player may make at once. RefillPerSecond: steady calls per second after that.

local Net = {
	RateLimits = table.freeze({
		-- Simulator "Lobby" button (ADR 0010). A second press while travelling is refused anyway;
		-- this only caps spam.
		TravelRequestLobby = table.freeze({ Burst = 2, RefillPerSecond = 0.5 }),
		-- Server -> client only. Clients never send on it, so the smallest budget is enough.
		TravelNotice = table.freeze({ Burst = 1, RefillPerSecond = 0.1 }),
	}),
}

return table.freeze(Net)

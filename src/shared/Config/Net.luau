--!strict
-- Per-remote rate limits and argument bounds for src/shared/Net.
-- Every remote declared in Net/Remotes takes its limit from RateLimits by its own name, so a
-- new remote without an entry here fails at startup instead of running unlimited.
--
-- Burst: calls a player may make at once. RefillPerSecond: steady calls per second after that.

local Net = {
	RateLimits = table.freeze({
		-- Simulator "Lobby" button (ADR 0011). A second press while travelling is refused anyway;
		-- this only caps spam.
		TravelRequestLobby = table.freeze({ Burst = 2, RefillPerSecond = 0.5 }),
		-- Server -> client only. Clients never send on it, so the smallest budget is enough.
		TravelNotice = table.freeze({ Burst = 1, RefillPerSecond = 0.1 }),
		-- Buy the next level of one upgrade (#36, ADR 0010). Allows quick repeated clicks on the
		-- buy button; the price and the level are decided on the server.
		UpgradeBuy = table.freeze({ Burst = 10, RefillPerSecond = 5 }),
		-- Server -> client pop-up (#90, ADR 0008). The client never sends it; there is no server
		-- handler, so a client call is dropped (NoHandler) after this limit.
		Popup = table.freeze({ Burst = 1, RefillPerSecond = 1 }),
		-- Server -> client sale result (#38, ADR 0012). Like Popup: no server handler, so a client
		-- call is dropped (NoHandler) after this limit.
		SaleResult = table.freeze({ Burst = 1, RefillPerSecond = 1 }),
		-- Onboarding hint done (#42, ADR 0017). A client sends it once per hint, so a small
		-- budget is plenty; repeats are refused anyway.
		TutorialHintDone = table.freeze({ Burst = 3, RefillPerSecond = 0.5 }),
	}),

	-- Pop-up remote (#90): a text key from Config.Ui.PopupTexts and up to MaxNumbers numbers.
	-- Technical bounds, not design values: MaxNumberMagnitude is the Coins MaxBalance
	-- (Config.Currency), so every balance or gain fits.
	Popup = table.freeze({
		MaxKeyLength = 64,
		MaxNumbers = 2,
		MaxNumberMagnitude = 1e30,
	}),

	-- Sale result remote (#38): the coins of one sale. Technical bound: the Coins MaxChange.
	Sale = table.freeze({
		MaxCoins = 1e30,
	}),
}

return table.freeze(Net)

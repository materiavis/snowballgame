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
		-- Buy the next level of one upgrade (#36, ADR 0010). Allows quick repeated clicks on the
		-- buy button; the price and the level are decided on the server.
		UpgradeBuy = table.freeze({ Burst = 10, RefillPerSecond = 5 }),
		-- Hatch one egg at the station the player stands at (#41, ADR 0013). A double tap reaches
		-- the server; its hatch cooldown (Config.Eggs) turns it into one purchase.
		EggHatch = table.freeze({ Burst = 3, RefillPerSecond = 2 }),
		-- Equip or unequip one pet (#41, ADR 0013). Allows quick taps through the pets window.
		PetEquip = table.freeze({ Burst = 10, RefillPerSecond = 5 }),
		-- Server -> client pop-up (#90, ADR 0008). The client never sends it; there is no server
		-- handler, so a client call is dropped (NoHandler) after this limit.
		Popup = table.freeze({ Burst = 1, RefillPerSecond = 1 }),
	}),

	-- EXAMPLE ONLY. Bounds for the example remote's arguments. Not design values.
	Example = table.freeze({
		MaxAmount = 10,
		MaxValues = 3,
		MaxValueMagnitude = 1000,
	}),

	-- Pop-up remote (#90): a text key from Config.Ui.PopupTexts and up to MaxNumbers numbers.
	-- Technical bounds, not design values: MaxNumberMagnitude is the Coins MaxBalance
	-- (Config.Currency), so every balance or gain fits.
	-- Pet uids (#41, ADR 0013): PetCore makes "<userId>_<time hex>_<random hex>", at most 36
	-- characters. Technical bound, not a design value.
	Pets = table.freeze({
		MaxUidLength = 48,
	}),

	Popup = table.freeze({
		MaxKeyLength = 64,
		MaxNumbers = 2,
		MaxNumberMagnitude = 1e30,
	}),
}

return table.freeze(Net)

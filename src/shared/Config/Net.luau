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
		-- Server -> client pop-up (#90, ADR 0008). The client never sends it; there is no server
		-- handler, so a client call is dropped (NoHandler) after this limit.
		Popup = table.freeze({ Burst = 1, RefillPerSecond = 1 }),
		-- Server -> client sale result (#38, ADR 0012). Like Popup: no server handler, so a client
		-- call is dropped (NoHandler) after this limit.
		SaleResult = table.freeze({ Burst = 1, RefillPerSecond = 1 }),
		-- Unlock the next zone at a barrier (#39, ADR 0014). One tap per unlock; a double tap is
		-- refused by ZoneService as already unlocked, the limit only stops floods.
		ZoneUnlock = table.freeze({ Burst = 3, RefillPerSecond = 1 }),
		-- Zone teleport (#39). ZoneService also refuses within Config.Zones.ZoneTeleportWait.
		ZoneTeleport = table.freeze({ Burst = 3, RefillPerSecond = 1 }),
		-- Server -> client find updates (#40, ADR 0016). Like Popup: no server handler, so a client
		-- call is dropped (NoHandler) after this limit.
		FindUpdate = table.freeze({ Burst = 1, RefillPerSecond = 1 }),
	}),

	-- Find update remote (#40): an action, then the point's slot, the find id and the position the
	-- action needs. Technical bounds, not design values: slots count up per server, ids are
	-- Config.Finds.Items keys (the client checks them again), positions are map coordinates.
	Finds = table.freeze({
		Actions = table.freeze({ "Spawn", "Remove", "Collect", "ClearBall", "Reset" }),
		MaxSlot = 1e6,
		MaxIdLength = 32,
		MaxPositionMagnitude = 1e6,
	}),

	-- Zone remotes (#39): the zone argument is a whole number 1..MaxZone. Technical bound, not a
	-- design value: it equals Config.Zones.ZoneCount (checked by a spec), and ZoneService checks
	-- the zone against the world, the map and the profile anyway.
	Zones = table.freeze({
		MaxZone = 50,
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

--!strict
-- THE list of remotes. Every RemoteEvent / RemoteFunction in the game is declared here and
-- nowhere else; NetService creates exactly these under ReplicatedStorage.Remotes.
--
-- Each entry needs:
--   kind      "Event" (client -> server FireServer) or "Function" (InvokeServer)
--   args      list of Net.Schema validators, one per argument; {} for none
--   rateLimit a Config.Net.RateLimits entry (per player)
--   authorize optional hook for ownership, distance, cooldowns and other game-state checks
--
-- This module is a function of its dependencies so the headless tests can load it with
-- plain path requires, while Net/init passes the Roblox modules. Config.Upgrades gives the
-- closed list of upgrade ids.

local function popupArgs(Schema: any, popup: any): { any }
	local args = { Schema.string({ minLength = 1, maxLength = popup.MaxKeyLength }) }
	for _ = 1, popup.MaxNumbers do
		table.insert(
			args,
			Schema.optional(Schema.number({ min = -popup.MaxNumberMagnitude, max = popup.MaxNumberMagnitude }))
		)
	end
	return args
end

return function(Schema: any, NetConfig: any, UpgradesConfig: any): { [string]: any }
	local example = NetConfig.Example

	return {
		-- EXAMPLE ONLY, not gameplay. Lets the playtester exercise the guard in Studio
		-- (NetExampleService handles it). Remove it once the first real remote exists.
		-- Args: a whole number 1..MaxAmount and a list of up to MaxValues bounded numbers.
		NetExample = {
			kind = "Event",
			args = {
				Schema.number({ min = 1, max = example.MaxAmount, integer = true }),
				Schema.array(
					Schema.number({ min = -example.MaxValueMagnitude, max = example.MaxValueMagnitude }),
					{ maxLength = example.MaxValues }
				),
			},
			rateLimit = NetConfig.RateLimits.NetExample,
		},

		-- Buy the next level of one upgrade (#36, ADR 0010). Arg: the upgrade id, one of
		-- Config.Upgrades.Order. No level or price is sent: UpgradeService reads the level from
		-- the profile and computes the price itself. Handled in the Simulator only; Lobby and
		-- Arena drop it as NoHandler.
		UpgradeBuy = {
			kind = "Event",
			args = { Schema.enum(UpgradesConfig.Order) },
			rateLimit = NetConfig.RateLimits.UpgradeBuy,
		},

		-- Unlock zone `zone` at the barrier at the end of zone - 1 (#39, ADR 0014). Arg: the zone
		-- to open. No price is sent: ZoneService checks world, cap, map, adjacency, the unlocked
		-- set and the coins itself and computes the price from Formulas.Zones.
		ZoneUnlock = {
			kind = "Event",
			args = { Schema.number({ min = 1, max = NetConfig.Zones.MaxZone, integer = true }) },
			rateLimit = NetConfig.RateLimits.ZoneUnlock,
		},

		-- Zone teleport (T, #39): to the start of an unlocked zone. ZoneService checks the unlock,
		-- the zone start and the wait after the last teleport.
		ZoneTeleport = {
			kind = "Event",
			args = { Schema.number({ min = 1, max = NetConfig.Zones.MaxZone, integer = true }) },
			rateLimit = NetConfig.RateLimits.ZoneTeleport,
		},

		-- Server -> client only (#90, ADR 0008): PopupService fires it with a text key from
		-- Config.Ui.PopupTexts and up to Config.Net.Popup.MaxNumbers numbers. No server handler
		-- exists, so a client call is dropped as NoHandler. The schema still bounds it.
		Popup = {
			kind = "Event",
			args = popupArgs(Schema, NetConfig.Popup),
			rateLimit = NetConfig.RateLimits.Popup,
		},

		-- Server -> client only (#38, ADR 0012): SellService fires it with the whole coins of one
		-- sale, and SaleController shows "+3.4K" flying to the Coins display. The server decides
		-- the sale from the ball touching a scale plate; no client asks for it. No server handler
		-- exists, so a client call is dropped as NoHandler. The schema still bounds it.
		SaleResult = {
			kind = "Event",
			args = { Schema.number({ min = 0, max = NetConfig.Sale.MaxCoins, integer = true }) },
			rateLimit = NetConfig.RateLimits.SaleResult,
		},

		-- Server -> client only (#40, ADR 0016): FindService tells one player about that player's
		-- own finds. Action "Spawn" (slot, find id, position), "Remove" (slot), "Collect" (slot,
		-- find id: it now sticks in the ball), "ClearBall" (the ball was sold) and "Reset" (drop
		-- every spawned find). The server decides spawns and pickups; no client asks for them. No
		-- server handler exists, so a client call is dropped as NoHandler. The schema still bounds it.
		FindUpdate = {
			kind = "Event",
			args = {
				Schema.enum(NetConfig.Finds.Actions),
				Schema.optional(Schema.number({ min = 1, max = NetConfig.Finds.MaxSlot, integer = true })),
				Schema.optional(Schema.string({ minLength = 1, maxLength = NetConfig.Finds.MaxIdLength })),
				Schema.optional(Schema.vector3({ maxMagnitude = NetConfig.Finds.MaxPositionMagnitude })),
			},
			rateLimit = NetConfig.RateLimits.FindUpdate,
		},
	}
end

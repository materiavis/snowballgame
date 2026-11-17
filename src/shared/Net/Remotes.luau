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
-- A server -> client event is declared the same way. It gets no server handler, so anything a
-- client fires on it is dropped (Rate, Arity or NoHandler) and counted.
--
-- This module is a function of its dependencies so the headless tests can load it with
-- plain path requires, while Net/init passes the Roblox modules. Config.Upgrades gives the
-- closed list of upgrade ids, Config.Tutorial the hint ids a client may report (#42).

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

return function(Schema: any, NetConfig: any, UpgradesConfig: any, TutorialConfig: any): { [string]: any }
	local limits = NetConfig.RateLimits

	return {
		-- Client -> server, no arguments: the Simulator "Lobby" button (ADR 0011). TravelService
		-- refuses it outside the Simulator and while a travel is in progress. The destination is
		-- always the Lobby, so the client has nothing to choose.
		TravelRequestLobby = {
			kind = "Event",
			args = {},
			rateLimit = limits.TravelRequestLobby,
		},

		-- Server -> client: TravelService sends one Config.Travel.Messages key (ADR 0011).
		TravelNotice = {
			kind = "Event",
			args = {},
			rateLimit = limits.TravelNotice,
		},

		-- Buy the next level of one upgrade (#36, ADR 0010). Arg: the upgrade id, one of
		-- Config.Upgrades.Order. No level or price is sent: UpgradeService reads the level from
		-- the profile and computes the price itself. Handled in the Simulator only; Lobby and
		-- Arena drop it as NoHandler.
		UpgradeBuy = {
			kind = "Event",
			args = { Schema.enum(UpgradesConfig.Order) },
			rateLimit = limits.UpgradeBuy,
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

		-- Client -> server (#42, ADR 0017): an onboarding hint whose action only the client can
		-- see is done (the Upgrades window opened). Arg: one of Config.Tutorial.ClientReportable.
		-- TutorialService accepts it only while that hint is showing for the player and only ever
		-- sets a known hint to done, never back. Lobby and Simulator handle it; the Arena drops it
		-- as NoHandler.
		TutorialHintDone = {
			kind = "Event",
			args = { Schema.enum(TutorialConfig.ClientReportable) },
			rateLimit = limits.TutorialHintDone,
		},
	}
end

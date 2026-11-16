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
-- closed list of upgrade ids.

return function(Schema: any, NetConfig: any, UpgradesConfig: any): { [string]: any }
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
	}
end

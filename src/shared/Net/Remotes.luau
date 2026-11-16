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

		-- Hatch one egg (#41, ADR 0013). No arguments: the server finds the egg station the
		-- character stands at, and decides price, coins, room and the roll itself. Handled in
		-- the Simulator only; Lobby and Arena drop it as NoHandler.
		EggHatch = {
			kind = "Event",
			args = {},
			rateLimit = NetConfig.RateLimits.EggHatch,
		},

		-- Equip (true) or unequip (false) one of the player's own pets by uid (#41, ADR 0013).
		-- PetService checks that the uid is in the player's inventory and that a slot is free.
		-- Handled where PetService runs (Lobby and Simulator); the Arena drops it as NoHandler.
		PetEquip = {
			kind = "Event",
			args = {
				Schema.string({ minLength = 1, maxLength = NetConfig.Pets.MaxUidLength }),
				Schema.boolean(),
			},
			rateLimit = NetConfig.RateLimits.PetEquip,
		},

		-- Server -> client only (#90, ADR 0008): PopupService fires it with a text key from
		-- Config.Ui.PopupTexts and up to Config.Net.Popup.MaxNumbers numbers. No server handler
		-- exists, so a client call is dropped as NoHandler. The schema still bounds it.
		Popup = {
			kind = "Event",
			args = popupArgs(Schema, NetConfig.Popup),
			rateLimit = NetConfig.RateLimits.Popup,
		},
	}
end

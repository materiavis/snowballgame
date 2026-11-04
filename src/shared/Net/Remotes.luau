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
-- plain path requires, while Net/init passes the Roblox modules.

return function(Schema: any, NetConfig: any): { [string]: any }
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
	}
end

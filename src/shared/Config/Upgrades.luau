--!strict
-- Coin upgrades (concept 7.8). Startwerte (✅ prices, factors and end values).
-- Cost of level L (1..MaxLevel) = BasePrice * Factor^(L - 1). The effect grows linearly from
-- Start at level 0 to End at MaxLevel (🟦).

export type Upgrade = {
	BasePrice: number,
	Factor: number,
	Start: number,
	End: number,
}

local Upgrades = {
	MaxLevel = 100,

	-- Ids match the save format (sim.upgrades).
	Order = table.freeze({ "growth", "walkSpeed", "magnet", "sellValue", "stability" }),

	Definitions = table.freeze({
		-- Seconds to the maximum on normal snow: 40 s to 8 s.
		growth = table.freeze({ BasePrice = 25, Factor = 1.35, Start = 40, End = 8 }),
		-- Walk speed in studs/s: 16 to 32.
		walkSpeed = table.freeze({ BasePrice = 40, Factor = 1.35, Start = 16, End = 32 }),
		-- Pickup radius for finds in studs: 4 to 24.
		magnet = table.freeze({ BasePrice = 150, Factor = 1.4, Start = 4, End = 24 }),
		-- Sell multiplier: +5 % per level, so 1.0 at level 0 and 6.0 at level 100.
		sellValue = table.freeze({ BasePrice = 200, Factor = 1.45, Start = 1, End = 6 }),
		-- Size lost per collision: 10 % to 2 %.
		stability = table.freeze({ BasePrice = 100, Factor = 1.35, Start = 0.1, End = 0.02 }),
	} :: { [string]: Upgrade }),
}

return table.freeze(Upgrades)

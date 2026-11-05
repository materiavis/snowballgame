--!strict
-- Currencies handled by CurrencyService (ADR 0007). Each entry says where the balance lives in
-- the profile (schema v1, ADR 0003) and the bounds every change is checked against.
-- Paths are part of the save format: they only change together with a Schema migration.
--
-- The bounds are technical guards, not game design: they stop a broken caller from writing
-- an absurd value into a profile. MaxChange is the largest single add or spend, MaxBalance the
-- largest balance; a balance that would pass it is held at it.
-- Coins reach about 1e22 at zone 50 (barrier 11 Sx, 8.3 formulas), so 1e30 leaves room for
-- every multiplier. Snow Coins stay below 2^53, so their sums are exact whole numbers.

export type Currency = {
	Path: { string },
	-- Total ever earned; spending and resets leave it alone (7.2 "most coins").
	TotalPath: { string }?,
	MaxChange: number,
	MaxBalance: number,
}

local Currency = {
	Currencies = table.freeze({
		Coins = table.freeze({
			Path = table.freeze({ "sim", "coins" }),
			TotalPath = table.freeze({ "sim", "totalCoins" }),
			MaxChange = 1e30,
			MaxBalance = 1e30,
		}),
		SnowCoins = table.freeze({
			Path = table.freeze({ "fight", "snowCoins" }),
			MaxChange = 1e6,
			MaxBalance = 1e15,
		}),
	} :: { [string]: Currency }),

	-- Longest reason string a caller may pass (it is logged and sent to analytics).
	MaxReasonLength = 64,
}

return table.freeze(Currency)

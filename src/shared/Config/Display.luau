--!strict
-- Number and size display (concept 7.4, 10.3), used by NumberFormat.
-- Fixed by the concept: from 1'000 on numbers are abbreviated K, M, B, T, Qa, Qi, Sx; ball
-- sizes show in m and km with one decimal and a decimal point, metres up to 999.9 m.
-- Not fixed by the concept (ADR 0007 assumptions): one decimal for abbreviated numbers, a
-- trailing ".0" dropped there, no space before the suffix ("+3.4K", "3.7M"), and rounding down.

local Display = {
	-- Each suffix is 1000 times the previous one. Numbers beyond the last suffix keep it
	-- ("1500Sx") instead of switching to scientific notation.
	Suffixes = table.freeze({ "K", "M", "B", "T", "Qa", "Qi", "Sx" }),
	SuffixStep = 1000,
	NumberDecimals = 1,
	TrimZeroDecimal = true,

	SizeDecimals = 1,
	MetresPerKilometre = 1000,
	MetreUnit = "m",
	KilometreUnit = "km",

	-- "Floor" never shows more than the value (a balance never looks larger than it is, and
	-- 999.95 m stays "999.9 m"); "Nearest" rounds half up. Either way the unit and suffix
	-- are chosen after rounding, so "1000K" or "1000.0 m" never appear.
	Rounding = "Floor" :: "Floor" | "Nearest",
}

return table.freeze(Display)

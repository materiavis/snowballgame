--!strict
-- Zones, barriers and worlds (concept 7.6, 8.3, 8.4) and zone optics (7.3). Startwerte.
-- The three knobs SizeGrowth (1.25), StrengthGrowth (1.2) and the balls per barrier
-- (BallsPerBarrierBase + BallsPerBarrierPerZone * n = 2 + 2n) are marked ✅: only game design
-- changes them (concept 7.6 Fix). Formulas that use these values are in Formulas/Zones.

local Zones = {
	ZoneCount = 50, -- 50 zones in 5 worlds
	ZonesPerWorld = 10,
	LaunchZoneCount = 10, -- World 1 at launch; the gate at the end of zone 10 is shown closed

	-- Maximum ball size of zone n in metres: MaxSizeBase * SizeGrowth^(n - 1).
	MaxSizeBase = 2,
	SizeGrowth = 1.25,

	-- Value of a ball in coins: BallValueFactor * size^3 (size in metres), so a full ball of
	-- zone n is 80 * 1.953^(n - 1).
	BallValueFactor = 10,

	-- Expected strength from pets and rebirths: M(n) = StrengthGrowth^(n - 1).
	StrengthGrowth = 1.2,

	-- Balls per barrier: B(n) = BallsPerBarrierBase + BallsPerBarrierPerZone * n.
	BallsPerBarrierBase = 2,
	BallsPerBarrierPerZone = 2,

	-- Zone teleport (T): wait after a teleport to a zone start, seconds.
	ZoneTeleportWait = 3,

	-- Highest zone a barrier may open (owner decision 2026-11-10 on #39 and the review of
	-- PR #106, ADR 0009 "Closed without a code change per Place"). A barrier at the end of zone n
	-- opens only if this Place has a valid zone area n + 1 and n + 1 <= HighestOpenZone. Vertical
	-- Slice: 5 (zones 1-5); #105 raises it for the Launch. Missing or invalid (not a whole number
	-- 1..ZoneCount): every barrier stays closed.
	HighestOpenZone = 5,

	-- Zone optics (7.3): OpticsBase + OpticsPerZone * (zone - 1) studs, at most VisualCap.
	-- Inside a zone the ball grows visually from OpticsStartFraction to 100 % of that.
	-- Development may lower VisualCap after the PR #7 playtest.
	OpticsBase = 4,
	OpticsPerZone = 0.94,
	VisualCap = 50,
	OpticsStartFraction = 0.4,

	-- Zone names shown under the progress bar (#90). Startwerte from the concept appendix, 🟦
	-- proposal: Game Design reviews them later. Index = zone; a zone without a name shows
	-- Config.Ui.Text.ZoneNamePlaceholder.
	Names = table.freeze({
		"Snowline",
		"Pine Forest",
		"Alpine Hut",
		"Mountain Lake",
		"Rocky Ridge",
		"Ski Slope",
		"Avalanche Slope",
		"Glacier Edge",
		"Glacier",
		"Summit",
	}),
}

return table.freeze(Zones)

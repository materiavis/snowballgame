--!strict
-- Ball pushing and growth (concept 7.3, 7.4). Startwerte. Speeds and distances in studs,
-- times in seconds, sizes in metres. Upgrade effects on these values are in Config/Upgrades.
-- The physics tuning of the prototype (PR #7, BallConfig) stays there until 7.3/7.4 move it.

local Ball = {
	WalkSpeed = 16, -- studs/s without upgrades (Walk speed upgrade goes to 32)
	JumpEnabled = false, -- no jumping in the Simulator (✅)
	-- MaxCountedSpeed (about 18 to 20 studs/s) is fixed by the PR #7 prototype, not here.

	StartSizeFraction = 0.1, -- start size: 10 % of the current zone's maximum
	TimeToMax = 40, -- seconds to the maximum on normal snow without upgrades
	DeepSnowGrowthMultiplier = 2, -- deep snow grows twice as fast
	TrackRegrowTime = 20, -- the own track regrows after this many seconds

	CollisionSizeLoss = 0.1, -- an obstacle costs 10 % size (Stability upgrade down to 2 %)
	CollisionProtection = 1, -- seconds without further loss after a collision
	KnockOverSizeRatio = 3, -- a ball at least 3x a small obstacle knocks it over
	KnockOverRespawn = 30, -- seconds until a knocked-over obstacle is back
}

return table.freeze(Ball)

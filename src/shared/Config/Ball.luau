--!strict
-- Ball pushing and growth (concept 7.3, 7.4). Startwerte. Speeds and distances in studs,
-- times in seconds, sizes in metres unless a name says studs. Upgrade effects on these values
-- are in Config/Upgrades. Zone optics (studs per zone, Visual Cap) are in Config/Zones.
-- The physics tuning below came from the PR #7 prototype (BallConfig) with #33 (ADR 0002)
-- and is free for Development to tune after playtests (7.3 Spielraum).

local Ball = {
	WalkSpeed = 16, -- studs/s without upgrades (Walk speed upgrade goes to 32)
	JumpEnabled = false, -- no jumping in the Simulator (✅)

	StartSizeFraction = 0.1, -- start size: 10 % of the current zone's maximum
	TimeToMax = 40, -- seconds to the maximum on normal snow without upgrades
	DeepSnowGrowthMultiplier = 2, -- deep snow grows twice as fast
	TrackRegrowTime = 20, -- the own track regrows after this many seconds

	CollisionSizeLoss = 0.1, -- an obstacle costs 10 % size (Stability upgrade down to 2 %)
	CollisionProtection = 1, -- seconds without further loss after a collision
	KnockOverSizeRatio = 3, -- a ball at least 3x a small obstacle knocks it over
	KnockOverRespawn = 30, -- seconds until a knocked-over obstacle is back

	-- Growth sampling (server). Only rolling on the ground counts, and only up to
	-- MaxCountedSpeed (concept 7.3: ca. 18 to 20 studs/s, fixed by the PR #7 prototype):
	-- faster movement (upgrades, game pass, exploits) is counted at this speed.
	SampleInterval = 0.1, -- seconds between server position samples
	MaxCountedSpeed = 20,
	MinDistancePerSample = 0.05, -- below this a sample is standing still / solver jitter
	GroundCheckMargin = 0.5, -- ground ray length = radius + margin + radius * per-radius margin
	GroundCheckMarginPerRadius = 0.02,

	-- Interim growth until #34 (7.4) replaces it: the server grows a size fraction 0..1 within
	-- the current zone by this much per counted stud. About 42 s at the base walk speed.
	PrototypeFractionPerStud = 0.0015,
	DefaultZone = 1, -- until ZoneService exists every ball is in zone 1
	-- The part is resized only when the visual diameter changed by this share of the current
	-- diameter, so the solver sees a few resizes per second at most instead of one per sample.
	ResizeStepFraction = 0.02,

	-- Physical material of the ball
	Density = 0.7,
	Friction = 0.6,
	Elasticity = 0,
	FrictionWeight = 1,
	ElasticityWeight = 100, -- makes the ball's zero elasticity win against the ground's

	-- Spawning and recovery (server)
	SpawnGroundSearchHeight = 50, -- ray starts this far above the character to find the ground
	ResetBelowY = -100, -- the ball is put back in front of its owner below this height
	-- The ball is put back in front of its owner if it stays this far (studs, beyond the hold
	-- distance) from the character for LeashTime seconds, e.g. stuck behind an obstacle.
	LeashDistance = 12,
	LeashTime = 2,

	-- Holding the ball in front of the character (client, applied to the ball it owns).
	-- Hold distance from the HumanoidRootPart centre to the ball centre = radius + HoldGap.
	HoldGap = 1.5,
	-- On a change of direction the ball swings around the character (never through it) to the
	-- new walking direction, at most this fast, with its centre moving sideways at most
	-- HoldMaxOrbitSpeedFactor * WalkSpeed, so a big ball swings slower.
	HoldTurnRateDegrees = 360,
	HoldMaxOrbitSpeedFactor = 2,
	-- Share of HoldMaxAcceleration a swing may use to keep the ball on its circle.
	HoldCentripetalShare = 0.5,
	-- Velocity controller: desired velocity = character velocity + (distance error, bearing
	-- error) * HoldPositionGain, at most HoldMaxSpeedFactor * WalkSpeed (push speed follows the
	-- walk speed); acceleration = velocity error * HoldVelocityGain, at most
	-- HoldMaxAcceleration. Force = acceleration * mass, so every size feels the same.
	HoldPositionGain = 6, -- 1/s
	HoldVelocityGain = 12, -- 1/s
	HoldMaxSpeedFactor = 3,
	-- studs/s². Holds the ball on slopes up to about 35° and keeps a far-off ball from being flung.
	HoldMaxAcceleration = 150,
	MoveDeadzone = 0.1, -- Humanoid.MoveDirection below this counts as standing still

	-- Camera (client): the zoom is kept at least so far that the whole ball fits in the
	-- narrower field of view, times CameraFitMargin. Only lifted while the ball needs it.
	CameraFitMargin = 1.25,
	CameraMaxZoomExtra = 20, -- studs of player zoom room above the required distance

	-- Names shared by server and client
	FolderName = "SnowBalls",
	OwnerAttribute = "OwnerUserId",
	ZoneAttribute = "Zone",
	SizeFractionAttribute = "SizeFraction",
	VisualDiameterAttribute = "VisualDiameter",
	RecoveriesAttribute = "Recoveries",

	-- Collision groups and rules (ADR 0003 rev. 2, "Ball collisions with foreign characters").
	-- The server registers the groups once; every client assigns them from its own view.
	CollisionGroups = {
		OwnCharacter = "OwnCharacter",
		OwnBall = "OwnBall",
		Balls = "Balls",
	},
	-- { groupA, groupB, collides }. Default is the world group every unassigned part is in.
	CollisionRules = {
		{ "OwnCharacter", "OwnBall", true },
		{ "OwnCharacter", "Balls", false },
		{ "OwnBall", "Balls", false },
		{ "Balls", "Balls", false },
		{ "OwnCharacter", "Default", true },
		{ "OwnBall", "Default", true },
		{ "Balls", "Default", true },
	},
}

for _, rule in Ball.CollisionRules do
	table.freeze(rule)
end
table.freeze(Ball.CollisionRules)
table.freeze(Ball.CollisionGroups)

return table.freeze(Ball)

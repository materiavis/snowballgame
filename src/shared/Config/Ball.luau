--!strict
-- Ball pushing and growth (concept 7.3, 7.4). Startwerte. Speeds and distances in studs,
-- times in seconds, sizes in metres unless a name says studs. Upgrade effects on these values
-- are in Config/Upgrades. Zone optics (studs per zone, Visual Cap) are in Config/Zones.
-- The physics tuning below came from the PR #7 prototype (BallConfig) with #33 (ADR 0002)
-- and is free for Development to tune after playtests (7.3 Spielraum).

local Ball = {
	WalkSpeed = 16, -- studs/s without upgrades (Walk speed upgrade goes to 32)
	JumpEnabled = false, -- no jumping in the Simulator (✅)

	-- The seconds to the maximum and the size lost per collision are upgrade effects: level 0
	-- of Config/Upgrades `growth` (40 s) and `stability` (10 %) is their only source.
	StartSizeFraction = 0.1, -- start size: 10 % of the current zone's maximum
	DeepSnowGrowthMultiplier = 2, -- deep snow grows twice as fast
	TrackRegrowTime = 20, -- the own track regrows after this many seconds

	CollisionProtection = 1, -- seconds without further loss after a collision
	KnockOverSizeRatio = 3, -- a ball at least 3x a small obstacle knocks it over
	KnockOverRespawn = 30, -- seconds until a knocked-over obstacle is back

	-- Growth sampling (server). Only rolling on the ground counts, and only up to
	-- MaxCountedSpeed (concept 7.3: ca. 18 to 20 studs/s, fixed by the PR #7 prototype):
	-- faster movement (upgrades, game pass, exploits) is counted at this speed.
	SampleInterval = 0.1, -- seconds between server position samples
	MaxCountedSpeed = 20,
	-- The speed limit is a credit of counted studs, refilled at MaxCountedSpeed and held for at
	-- most this many seconds. The position of a client-owned ball reaches the server in uneven
	-- packets, so a limit per sample throws away real distance (ADR 0002 "Calibration").
	CountedBurstWindow = 0.5,
	MinDistancePerSample = 0.05, -- below this a sample is standing still / solver jitter
	GroundCheckMargin = 0.5, -- ground ray length = radius + margin + radius * per-radius margin
	GroundCheckMarginPerRadius = 0.02,

	DefaultZone = 1, -- until ZoneService exists every ball is in zone 1
	-- The part is resized only when the visual diameter changed by this share of the current
	-- diameter, so the solver sees a few resizes per second at most instead of one per sample.
	ResizeStepFraction = 0.02,

	-- Character at the ball (7.4). The HumanoidRootPart counts as at the ball within GrowthRange
	-- studs of the ball's edge, measured on the ground plane, so the same number works for every
	-- ball size. Holding the ball puts the character HoldGap (1.5) from the edge; the rest is
	-- room for turning and for character and ball arriving in different packets.
	GrowthRange = 6,
	-- And at most this far above or below the top or bottom of the ball.
	GrowthVerticalRange = 8,

	-- Surfaces (ADR 0003 D3): CollectionService tags on the ground parts. A part with several
	-- of them counts as the first one in SurfacePriority.
	Surfaces = { Snow = "Snow", DeepSnow = "DeepSnow", Ice = "Ice", Grass = "Grass" },
	SurfacePriority = { "DeepSnow", "Snow", "Ice", "Grass" },

	-- Track (per player, logical, ADR 0002 "Track"). A cell becomes track when the contact point
	-- has left it. 4 studs: 2.5 samples at the base walk speed, and about the width of a full
	-- zone 1 ball.
	TrackCellSize = 4,
	-- The contact point must be this far past a cell's edge before it changes cell, so rolling
	-- straight along a cell border does not flip between two cells and hit its own track.
	TrackCellHysteresis = 0.5,
	-- Rolled studs that one cell yields. A straight crossing is at most about 6.7 (diagonal plus
	-- hysteresis), so only rolling back and forth inside one cell reaches this.
	TrackMaxRolledPerCell = 8,

	-- Obstacles (7.4). All carry ObstacleTag. A small one also has the number attribute
	-- KnockOverSizeAttribute: its size in studs, compared with the ball's visual diameter.
	ObstacleTag = "Obstacle",
	KnockOverSizeAttribute = "KnockOverSize",
	CollisionContactMargin = 0.25, -- studs of slack on the server's view of the contact
	KnockOverRetryInterval = 1, -- seconds between tries while a ball is where it would return

	-- MAX feedback (7.4). The arrow points at the nearest instance with this tag.
	ScaleAnchorTag = "ScaleAnchor",
	-- Empty: no sound. Needs a licensed asset (open question on #34).
	MaxSoundId = "",
	MaxSoundVolume = 0.5,
	MaxGlowColorRGB = { 255, 236, 150 },
	MaxGlowBrightness = 3,
	MaxGlowRangeMin = 12,
	MaxGlowRangeMax = 60, -- the Roblox limit for a PointLight
	MaxGlowRangePerDiameter = 1.5,
	MaxGlowFillTransparency = 0.6,
	MaxText = "MAX!",
	MaxArrowColorRGB = { 255, 210, 60 },
	MaxArrowAboveBall = 3, -- studs above the top of the ball
	MaxArrowHeadLength = 2.5,
	MaxArrowHeadRadius = 1.2,
	MaxArrowShaftLength = 3,
	MaxArrowShaftRadius = 0.4,

	-- Minimal size label (top centre, 7.4) until the HUD integrates the published size.
	SizeLabelWidth = 220,
	SizeLabelHeight = 36,
	SizeLabelTopOffset = 8,
	MaxLabelHeight = 28,
	SizeLabelTextRGB = { 255, 255, 255 },
	MaxLabelTextRGB = { 255, 210, 60 },
	SizeLabelTextStrokeTransparency = 0.5,

	-- The published size and the Studio diagnostics are refreshed at this interval (seconds).
	PublishInterval = 0.25,

	-- Look of the ball. Plain values so this module also loads outside Roblox (Lune tests).
	ColorRGB = { 245, 248, 255 },
	MaterialName = "Snow", -- an Enum.Material name

	-- Physical material of the ball
	Density = 0.7,
	Friction = 0.6,
	Elasticity = 0,
	FrictionWeight = 1,
	ElasticityWeight = 100, -- makes the ball's zero elasticity win against the ground's

	-- Spawning and recovery (server)
	SpawnGroundSearchHeight = 50, -- ray starts this far above the character to find the ground
	SpawnGroundSearchDepthFactor = 4, -- and reaches SpawnGroundSearchHeight * this downwards
	SpawnFallbackGroundOffset = 3, -- no ground found: assume it this far below the root part
	ResetBelowY = -100, -- the ball is put back in front of its owner below this height
	-- The ball is put back in front of its owner if it stays this far (studs, beyond the hold
	-- distance) from the character for LeashTime seconds.
	LeashDistance = 12,
	LeashTime = 2,

	-- Safe put-back position (#94, ADR 0002 "Recovery"). Proposals until the owner confirms them
	-- after the playtest. Candidates lie around the character: straight in front first, then
	-- every RecoveryBearingStepDegrees alternating left and right up to straight behind, each at
	-- the hold distance plus every RecoveryRingSteps entry. 30° gives 12 bearings; +3 studs keeps
	-- the ball's edge at HoldGap + 3 = 4.5, inside GrowthRange (6).
	RecoveryBearingStepDegrees = 30,
	RecoveryRingSteps = { 0, 3 },
	-- Ground must also be found at four points this share of the radius from the centre, at
	-- most RecoverySupportSlope × that offset above or below the centre's ground (1 = 45°), so
	-- the ball does not sit on the rim of a cliff or hole.
	RecoverySupportShare = 0.5,
	RecoverySupportSlope = 1,
	-- Studs between a put-back ball and an Obstacle, above CollisionContactMargin (0.25) so the
	-- first sample after the placement sees no contact (#34 finding: placed 0.1 stud inside).
	RecoveryObstacleClearance = 0.5,
	-- Other block parts may touch the put-back ball by this much (the ground it rests on).
	RecoveryPenetrationTolerance = 0.05,
	-- No fall check for this long after a placement: owner packets sent before it can still
	-- show the old position. A ball needs about 1 s to fall from the ground to ResetBelowY.
	RecoveryGraceTime = 0.5,
	-- At most RecoveryBurstLimit recoveries within RecoveryBurstWindow seconds. The next one in
	-- the window still puts the ball back, then parks it (anchored) for RecoveryParkTime so it
	-- cannot fall again at once. Run A of #33 had 5 within about 2 s; a ball pushed off an edge
	-- by hand again and again needs about 4 s per round at diameter 50 (swing and fall).
	RecoveryBurstLimit = 3,
	RecoveryBurstWindow = 5,
	RecoveryParkTime = 3,
	-- Loop bound (#94 round 1, proposals): the burst rule misses a loop with a few seconds per
	-- round (playtest at f95545a: falls about 5 s apart at the map edge). A recovery whose
	-- put-back position lies within max(RecoveryLoopRadiusMin, diameter ×
	-- RecoveryLoopRadiusPerDiameter) studs of RecoveryLoopLimit earlier put-backs inside
	-- RecoveryLoopWindow seconds is past the bound and parks like the burst rule. "Near the same
	-- place" keeps a player who loses the ball now and then across the map below it. With 3 in
	-- 40 s a loop of up to about 13 s per round is parked at its 4th recovery (15 s into a 5 s
	-- loop). A player who deliberately pushes the ball off the same edge every few seconds is
	-- parked too: the server cannot tell that from the loop, and parking only holds the ball
	-- for RecoveryParkTime. Normal play (playtest normal-play check) has no recoveries at all.
	RecoveryLoopLimit = 3,
	RecoveryLoopWindow = 40,
	RecoveryLoopRadiusMin = 10,
	RecoveryLoopRadiusPerDiameter = 1,
	-- Client: after the server put the ball back, the hold follows the ball's new bearing for
	-- this long while the player stands still, so it is not swung back over the edge (#94).
	-- Covers the put-back position and the Recoveries attribute arriving a few frames apart.
	RecoveryHoldResetTime = 0.5,
	-- Stuck (#94 AC8): out of the character's growth range for StuckTime seconds while the ball
	-- neither moved StuckProgressStuds nor came that much closer, e.g. held behind an obstacle.
	StuckTime = 4,
	StuckProgressStuds = 2,
	-- Stuck reach on slopes (#94 round 2, proposal). Outside the growth range only by height, a
	-- ball still counts as held (not stuck) when the ground under it is at most
	-- GrowthVerticalRange plus a slope this steep over the ground-plane distance away from the
	-- character's ground. 40° is above the 25° test ramp and the about 35° the hold can keep a
	-- ball on (HoldMaxAcceleration), and far below a cliff: at the farthest held distance of a
	-- 50-stud ball (radius + GrowthRange = 31) it allows 8 + 26 = 34 studs, the test cliff is 70.
	-- The growth range itself (7.4) is unchanged. The character's ground is searched at most
	-- GrowthVerticalRange below the root part; above it the character counts as airborne.
	StuckSlopeDegrees = 40,

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
	-- narrower field of view on every bearing around the camera focus, times CameraFitMargin.
	-- Only lifted while the ball needs it.
	CameraFitMargin = 1.1,
	CameraMaxZoomExtra = 20, -- studs of player zoom room above the required distance
	-- Camera focus above the ground the ball rests on (Roblox aims about 1.5 above the root part).
	CameraFocusHeightMin = 3,
	CameraFocusHeightMax = 6,
	-- The push back after the default occlusion: skipped within this many studs of the required
	-- distance, and stops this many studs before a real wall.
	CameraPushTolerance = 0.05,
	CameraWallClearance = 0.5,

	-- Names shared by server and client
	FolderName = "SnowBalls",
	OwnerAttribute = "OwnerUserId",
	ZoneAttribute = "Zone",
	SizeFractionAttribute = "SizeFraction",
	VisualDiameterAttribute = "VisualDiameter",
	RecoveriesAttribute = "Recoveries",
	-- Server placements that are not recoveries (spawn, respawn, Studio switch
	-- BallPlaceBehindObstacle).
	-- The client hold follows the ball after a change, as after a Recoveries change.
	PlacementsAttribute = "Placements",
	SizeMetresAttribute = "SizeMetres", -- on the ball
	IsMaxAttribute = "IsMax", -- on the ball
	-- On the Player, so any HUD can read the size without finding the ball.
	PlayerSizeMetresAttribute = "BallSizeMetres",
	PlayerSizeFractionAttribute = "BallSizeFraction",
	PlayerIsMaxAttribute = "BallIsMax",
	PlayerScaleAnchorAttribute = "BallScaleAnchor", -- Vector3, set when the ball reaches MAX
	-- Read-only diagnostics on the ball, written only in Studio at PlaceId 0.
	DiagnosticAttributes = {
		Surface = "Surface",
		GrowthCounts = "GrowthCounts",
		GrowthBlock = "GrowthBlock",
		LastCollisionLoss = "LastCollisionLoss",
		Collisions = "Collisions",
		KnockOvers = "KnockOvers",
		TrackCells = "TrackCells",
		RolledStuds = "RolledStuds",
		CountedStuds = "CountedStuds",
		GrowthSeconds = "GrowthSeconds",
		MeasuredTimeToMax = "MeasuredTimeToMax",
		LastRecovery = "LastRecovery", -- reason of the last recovery
		RecoverySpot = "RecoverySpot", -- Front, Around, LastSafe or Unsafe
		StuckFor = "StuckFor", -- seconds the stuck timer has run
		Parked = "Parked", -- true while the recovery bound holds the ball
	},

	-- Collision groups and rules: ADR 0003 rev. 2 ("Ball collisions with foreign characters"),
	-- extended in ADR 0002 by OtherCharacters (concept 7.3 ✅: characters walk through foreign
	-- balls, nobody can block anyone). The server registers the groups once; every client
	-- assigns them from its own view. The server keeps balls in Balls, characters in Default.
	CollisionGroups = {
		OwnCharacter = "OwnCharacter",
		OwnBall = "OwnBall",
		Balls = "Balls",
		OtherCharacters = "OtherCharacters",
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
		{ "OwnBall", "OtherCharacters", false },
		{ "OwnCharacter", "OtherCharacters", false },
		{ "Balls", "OtherCharacters", false },
		{ "OtherCharacters", "OtherCharacters", false },
		{ "OtherCharacters", "Default", true },
	},
}

for _, rule in Ball.CollisionRules do
	table.freeze(rule)
end
table.freeze(Ball.CollisionRules)
table.freeze(Ball.CollisionGroups)
table.freeze(Ball.ColorRGB)
table.freeze(Ball.Surfaces)
table.freeze(Ball.SurfacePriority)
table.freeze(Ball.MaxGlowColorRGB)
table.freeze(Ball.MaxArrowColorRGB)
table.freeze(Ball.SizeLabelTextRGB)
table.freeze(Ball.MaxLabelTextRGB)
table.freeze(Ball.DiagnosticAttributes)
table.freeze(Ball.RecoveryRingSteps)

return table.freeze(Ball)

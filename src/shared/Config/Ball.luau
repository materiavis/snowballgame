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
	MaxArrowColorRGB = { 255, 210, 60 },
	MaxArrowAboveBall = 3, -- studs above the top of the ball
	MaxArrowHeadLength = 2.5,
	MaxArrowHeadRadius = 1.2,
	MaxArrowShaftLength = 3,
	MaxArrowShaftRadius = 0.4,

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
table.freeze(Ball.DiagnosticAttributes)

return table.freeze(Ball)

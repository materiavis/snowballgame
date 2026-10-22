--!strict
-- Tuning values for the growing snowball prototype (#3).
-- All numbers are placeholders to be tuned in playtests. Sizes are diameters in studs.

local BallConfig = {}

-- Size and growth (server)
BallConfig.StartDiameter = 4
-- Diameter added per stud the ball rolls on the ground.
BallConfig.GrowthPerStud = 0.05
-- Physical size is only changed once the pending growth reaches this many studs of diameter,
-- so the physics solver sees a few discrete resizes instead of one every frame.
BallConfig.GrowthStep = 0.25
-- Above this diameter the physical/visual ball stops growing; the internal size keeps increasing
-- and the client shows a "×N" multiplier. Roblox parts are limited to 2048 studs per axis.
BallConfig.VisualCapDiameter = 50

-- Distance measurement (server)
BallConfig.SampleInterval = 0.1 -- seconds between server position samples
-- Movement faster than this (studs/s) between two samples is ignored for growth (anti-exploit).
-- Kept just above PushMaxSpeed so legit pushing counts but little else does.
BallConfig.MaxCountedSpeed = 20
-- Movement below this many studs per sample is treated as standing still / solver jitter.
BallConfig.MinDistancePerSample = 0.05
-- Ground check: ray from the ball center straight down, length = radius + margin.
BallConfig.GroundCheckMargin = 0.5
BallConfig.GroundCheckMarginPerRadius = 0.02

-- Physical material of the ball
BallConfig.Density = 0.7
BallConfig.Friction = 0.6
BallConfig.Elasticity = 0
BallConfig.FrictionWeight = 1
BallConfig.ElasticityWeight = 100 -- makes the ball's zero elasticity win against the ground's

-- Spawning / recovery (server)
BallConfig.SpawnGapFromCharacter = 3 -- studs between character and ball surface on spawn
BallConfig.SpawnGroundSearchHeight = 50 -- ray starts this far above the character to find the ground
BallConfig.ResetBelowY = -100 -- ball is put back next to its owner if it falls below this height

-- Pushing (client, applied to the ball the player owns)
-- Push force = PushAcceleration * ball mass, so a big ball feels as responsive as a small one.
BallConfig.PushAcceleration = 40
-- Stop adding push force above this horizontal speed. Kept below Humanoid.WalkSpeed (16)
-- so the character keeps up and stays at the ball's surface.
BallConfig.PushMaxSpeed = 14
-- Pull sideways velocity towards zero while pushing (1/s), so the ball follows the move direction.
BallConfig.PushSteerGain = 4
-- Contact range = gap between the HumanoidRootPart and the ball surface.
-- Against a large sphere the gap levels out around 2 studs, so a small base plus a small radius term is enough.
BallConfig.ContactRangeBase = 3
BallConfig.ContactRangePerRadius = 0.05
-- Minimum dot product between move direction and the direction to the ball (ball must be in front).
BallConfig.PushMinFacingDot = 0.2
-- Deceleration applied when nobody pushes, since Roblox has no rolling resistance.
BallConfig.BrakeAcceleration = 8
BallConfig.BrakeMinSpeed = 0.5

-- Names shared by server and client
BallConfig.CollisionGroup = "SnowBalls"
BallConfig.FolderName = "SnowBalls"
BallConfig.OwnerAttribute = "OwnerUserId"
BallConfig.SizeAttribute = "InternalSize"

return table.freeze(BallConfig)

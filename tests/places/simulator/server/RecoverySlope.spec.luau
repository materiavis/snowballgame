--!strict
-- Slopes in the recovery (issue #94 correction round 2, ADR 0002 "Recovery"). The playtest at
-- 30f6833 stood a character still on the 25° test ramp with the 50-stud ball held in front:
-- the stuck rule fired every 4 to 7 s and every put-back candidate was `Unsafe`. A model of
-- the TestGeometry ramp, platform and map ground stands in for the rays.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local RecoveryRules = require("../../../../src/places/simulator/server/BallService/RecoveryRules")
local GrowthRules = require("../../../../src/places/simulator/server/BallService/GrowthRules")

local rules = RecoveryRules.new(BallConfig :: any)
local growthRules = GrowthRules.new(BallConfig :: any, function(_zone: number): number
	return 1
end)

local DIAMETER = 50
local RADIUS = DIAMETER / 2
local ROOT_HEIGHT = 3 -- root part centre above the ground (R15 default)
local RAMP = math.rad(25)
local TAN = math.tan(RAMP)

local function holdDistance(diameter: number): number
	return diameter / 2 + BallConfig.HoldGap
end

-- TestGeometry: platform x -320..-200, z -210..-90, top 70; ramp from x -200 (y 70) down to
-- x about -50 (y 0) at z -180..-120; map ground y 0 elsewhere. Returns height and normal Y.
local function ground(x: number, z: number): (number?, number)
	if x >= -320 and x <= -200 and z >= -210 and z <= -90 then
		return 70, 1
	end
	local rampY = (-50 - x) * TAN
	if x > -200 and rampY > 0 and z >= -180 and z <= -120 then
		return rampY, math.cos(RAMP)
	end
	if math.abs(x) <= 1024 and math.abs(z) <= 1024 then
		return 0, 1
	end
	return nil, 0
end

-- Distance from a ball centre to the ramp's top plane (the box face SafeSpot measures).
local function rampDistance(x: number, y: number): number
	return (y - (-50 - x) * TAN) * math.cos(RAMP)
end

-- What SafeSpot.find does, without obstacles: first candidate whose resting centre is
-- supported, does not reach into the ramp and is in the character's growth range.
local function choose(rootX: number, rootZ: number, lookX: number, lookZ: number)
	local rootY = (ground(rootX, rootZ) :: number) + ROOT_HEIGHT
	for _, candidate in rules.candidates(lookX, lookZ, holdDistance(DIAMETER)) do
		local x, z = rootX + candidate.x, rootZ + candidate.z
		local centreGround, normalY = ground(x, z)
		local centreY = if centreGround then rules.restingHeight(centreGround, normalY, RADIUS) else nil
		if centreGround and centreY then
			local supports: { [number]: number? } = {}
			for index, offset in rules.supportOffsets(RADIUS) do
				supports[index] = (ground(x + offset.x, z + offset.z))
			end
			local _, onRamp = ground(x, z)
			local intoRamp = onRamp < 1 and rules.blocksPlacement(rampDistance(x, centreY), RADIUS, false)
			local horizontal = math.sqrt(candidate.x * candidate.x + candidate.z * candidate.z)
			if
				rules.isSupported(centreGround, supports, RADIUS)
				and not intoRamp
				and growthRules.inGrowthRange(horizontal, rootY - centreY, DIAMETER)
			then
				return candidate, { x = x, y = centreY, z = z }
			end
		end
	end
	return nil, nil
end

-- The playtest: character standing at x -160 on the ramp, facing uphill (-X), the ball held
-- at the hold distance in front of it, resting on the ramp.
local ROOT_X, ROOT_Z = -160, -150
local function heldUphill()
	local characterGround = ground(ROOT_X, ROOT_Z) :: number
	local ballX = ROOT_X - holdDistance(DIAMETER)
	local ballGround, normalY = ground(ballX, ROOT_Z)
	local centreY = rules.restingHeight(ballGround :: number, normalY, RADIUS) :: number
	return characterGround, ballGround :: number, centreY, holdDistance(DIAMETER)
end

return T.suite("Simulator recovery on slopes (7.3, #94)", function(test)
	test("resting height: radius on flat ground, radius / cos on a slope, nothing on a wall", function()
		T.near(rules.restingHeight(10, 1, RADIUS) :: number, 10 + RADIUS, 1e-9)
		T.near(rules.restingHeight(10, math.cos(RAMP), RADIUS) :: number, 10 + RADIUS / math.cos(RAMP), 1e-9)
		T.equal(rules.restingHeight(10, 0, RADIUS), nil, "wall")
		T.equal(rules.restingHeight(10, -1, RADIUS), nil, "overhang")
		T.equal(rules.restingHeight(10, 0 / 0, RADIUS), nil, "NaN")
	end)

	test("cause 2: placed at radius above a ramp hit, the ball reaches into the ramp", function()
		local x = -150
		local groundY = (ground(x, ROOT_Z)) :: number
		T.isTrue(rules.blocksPlacement(rampDistance(x, groundY + RADIUS), RADIUS, false), "old height rejected")
		local fixed = rules.restingHeight(groundY, math.cos(RAMP), RADIUS) :: number
		T.near(rampDistance(x, fixed), RADIUS, 1e-9, "touches the ramp")
		T.equal(rules.blocksPlacement(rampDistance(x, fixed), RADIUS, false), false, "new height accepted")
	end)

	test("cause 1: a ball held uphill on the ramp is outside the growth range by height alone", function()
		local characterGround, _, centreY, horizontal = heldUphill()
		local rootY = characterGround + ROOT_HEIGHT
		T.equal(growthRules.inGrowthRange(horizontal, rootY - centreY, DIAMETER), false, "growth range says no")
		T.isTrue(horizontal - RADIUS <= BallConfig.GrowthRange, "but in range on the ground plane")
	end)

	test("held on the ramp counts as in reach, so the stuck rule never fires while standing", function()
		local characterGround, ballGround, _, horizontal = heldUphill()
		T.equal(rules.heldOnSlope(horizontal, ballGround, characterGround, DIAMETER), true)
		local tracker: any = nil
		local stuck = false
		for _ = 1, 300 do -- 30 s of samples, ball still
			tracker, stuck = rules.stuckStep(tracker, {
				inRange = rules.heldOnSlope(horizontal, ballGround, characterGround, DIAMETER),
				distance = horizontal,
				x = ROOT_X - horizontal,
				z = ROOT_Z,
				elapsed = BallConfig.SampleInterval,
			})
			T.equal(stuck, false)
		end
		-- Also held downhill and across the ramp.
		for _, ballX in { ROOT_X + horizontal, ROOT_X } do
			local downGround = ground(ballX, ROOT_Z) :: number
			T.equal(rules.heldOnSlope(horizontal, downGround, characterGround, DIAMETER), true, `ball at x {ballX}`)
		end
	end)

	test("a ball at the foot of the cliff is still not held: the stuck rule stays", function()
		-- Character at the -Z edge of the platform, ball below it on the map ground.
		for _, horizontal in { holdDistance(DIAMETER), RADIUS + BallConfig.GrowthRange } do
			T.equal(rules.heldOnSlope(horizontal, 0, 70, DIAMETER), false, `horizontal {horizontal}`)
		end
	end)

	test("a ball held behind an obstacle on flat ground is not held (AC8 unchanged)", function()
		local horizontal = RADIUS + BallConfig.GrowthRange + 0.5
		T.equal(rules.heldOnSlope(horizontal, 0, 0, DIAMETER), false)
	end)

	test("no ground under ball or character: only the growth range decides", function()
		T.equal(rules.heldOnSlope(20, nil, 0, DIAMETER), false)
		T.equal(rules.heldOnSlope(20, 0, nil, DIAMETER), false)
	end)

	test("the slope limit is above the test ramp and far below the test cliff", function()
		T.isTrue(BallConfig.StuckSlopeDegrees > 25)
		local allowed = BallConfig.GrowthVerticalRange
			+ (RADIUS + BallConfig.GrowthRange) * math.tan(math.rad(BallConfig.StuckSlopeDegrees))
		T.isTrue(allowed < 70, `largest allowed height difference {allowed} < cliff 70`)
	end)

	test("a safe spot is found on the ramp, not reaching into it and in growth range", function()
		local candidate, centre = choose(ROOT_X, ROOT_Z, -1, 0)
		T.isTrue(candidate ~= nil, "a spot on the ramp")
		local c = centre :: { x: number, y: number, z: number }
		T.isTrue(rampDistance(c.x, c.y) >= RADIUS - 1e-6, "touches, does not reach into the ramp")
		-- Facing downhill the spot straight in front is fine.
		local front = choose(ROOT_X, ROOT_Z, 1, 0)
		T.isTrue(front ~= nil and front.bearing == 0, "Front when facing downhill")
	end)
end)

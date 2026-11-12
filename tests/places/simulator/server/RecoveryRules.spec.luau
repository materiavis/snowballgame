--!strict
-- RecoveryRules (issue #94, concept 7.3, ADR 0002 "Recovery"): candidate order, ground support,
-- obstacle clearance, the recovery bound and the stuck rule, on the real Config. A small 2D
-- ground model (map edge, hole, cliff) stands in for SafeSpot's rays.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local RecoveryRules = require("../../../../src/places/simulator/server/BallService/RecoveryRules")
local ObstacleRules = require("../../../../src/places/simulator/server/BallService/ObstacleRules")
local GrowthRules = require("../../../../src/places/simulator/server/BallService/GrowthRules")

local rules = RecoveryRules.new(BallConfig :: any)
local obstacleRules = ObstacleRules.new(BallConfig :: any)
local growthRules = GrowthRules.new(BallConfig :: any, function(_zone: number): number
	return 1
end)

local DIAMETER = 50 -- the Visual Cap ball of run A
local MAP_EDGE = 1024 -- placeholder ground 2048 x 2048, top at y 0
local GRAVITY = 196.2 -- Roblox default Workspace.Gravity
local ROOT_HEIGHT = 3 -- root part centre above the ground (R15 default)

local function holdDistance(diameter: number): number
	return diameter / 2 + BallConfig.HoldGap
end

type Ground = (x: number, z: number) -> number?

-- Placeholder map: flat at y 0 inside the edge, nothing outside.
local function mapGround(x: number, z: number): number?
	if math.abs(x) <= MAP_EDGE and math.abs(z) <= MAP_EDGE then
		return 0
	end
	return nil
end

-- The TestGeometry hole pier: floor beyond the -Z edge with a hole into the void.
local function pierGround(x: number, z: number): number?
	if mapGround(x, z) then
		return 0
	end
	local onPier = math.abs(x) <= 80 and z <= -1024 and z >= -1184
	local inHole = math.abs(x) < 30 and z < -1074 and z > -1134
	return if onPier and not inHole then 0 else nil
end

-- The TestGeometry cliff: platform top y 70 at x -320..-200, ground y 0 elsewhere.
local function cliffGround(x: number, z: number): number?
	if x >= -320 and x <= -200 and z >= -210 and z <= -90 then
		return 70
	end
	return mapGround(x, z)
end

-- What SafeSpot.find does with the rays, without obstacles: first supported candidate in the
-- character's growth range, or nil.
local function choose(ground: Ground, rootX: number, rootZ: number, lookX: number, lookZ: number, diameter: number)
	local radius = diameter / 2
	local rootY = (ground(rootX, rootZ) or 0) + ROOT_HEIGHT
	for _, candidate in rules.candidates(lookX, lookZ, holdDistance(diameter)) do
		local x, z = rootX + candidate.x, rootZ + candidate.z
		local centreGround = ground(x, z)
		local supports: { [number]: number? } = {}
		for index, offset in rules.supportOffsets(radius) do
			supports[index] = ground(x + offset.x, z + offset.z)
		end
		if rules.isSupported(centreGround, supports, radius) then
			local horizontal = math.sqrt(candidate.x * candidate.x + candidate.z * candidate.z)
			local centreY = (centreGround :: number) + radius
			if growthRules.inGrowthRange(horizontal, rootY - centreY, diameter) then
				return candidate, x, z
			end
		end
	end
	return nil, 0, 0
end

return T.suite("Simulator RecoveryRules (7.3, #94)", function(test)
	test("candidates: straight in front first, then alternating sides, straight behind last", function()
		local list = rules.candidates(0, -1, 10)
		T.equal(#list, 12 * #BallConfig.RecoveryRingSteps, "12 bearings per ring at 30°")
		T.equal(list[1].bearing, 0)
		T.near(list[1].x, 0, 1e-9, "front x")
		T.near(list[1].z, -10, 1e-9, "front z at the hold distance")
		local bearings = {}
		for index = 1, #list, #BallConfig.RecoveryRingSteps do
			table.insert(bearings, list[index].bearing)
		end
		T.equal(table.concat(bearings, ","), "0,30,-30,60,-60,90,-90,120,-120,150,-150,180")
		local behind = list[#list]
		T.near(behind.z, 10 + BallConfig.RecoveryRingSteps[#BallConfig.RecoveryRingSteps], 1e-9, "behind")
	end)

	test("candidates: no facing direction falls back to -Z; every ring is in growth range", function()
		local list = rules.candidates(0, 0, 10)
		T.near(list[1].z, -10, 1e-9)
		for _, ring in BallConfig.RecoveryRingSteps do
			local distance = holdDistance(DIAMETER) + ring
			T.isTrue(growthRules.inGrowthRange(distance, 0, DIAMETER), `ring +{ring} in range`)
			T.isTrue(growthRules.inGrowthRange(holdDistance(1.6) + ring, 0, 1.6), `ring +{ring} small ball`)
		end
	end)

	test("support: centre and all four points need ground within the slope", function()
		local radius = 10
		local allowed = radius * BallConfig.RecoverySupportShare * BallConfig.RecoverySupportSlope
		T.equal(rules.isSupported(nil, { 0, 0, 0, 0 }, radius), false, "no ground at the centre")
		T.equal(#rules.supportOffsets(radius), 4)
		T.equal(rules.isSupported(0, { 0, 0, 0, nil }, radius), false, "last point over a hole")
		T.equal(rules.isSupported(0, { [1] = 0, [3] = 0, [4] = 0 }, radius), false, "second point over a hole")
		T.equal(rules.isSupported(0, { 0, 0, 0, 0 }, radius), true, "flat")
		T.equal(rules.isSupported(0, { allowed, -allowed, 0, 0 }, radius), true, "slope at the limit")
		T.equal(rules.isSupported(0, { 0, -(allowed + 0.1), 0, 0 }, radius), false, "drop past the limit")
	end)

	test("run A: character at the map edge facing out, diameter 50, the ball stays on the map", function()
		-- Old rule: straight in front, without ground: in the air, falls again (the loop).
		local front = rules.candidates(0, -1, holdDistance(DIAMETER))[1]
		T.equal(mapGround(0, -1000 + front.z), nil, "the old spot in front has no ground")
		for _, rootZ in { -998, -1005, -1015, -1023 } do
			for _, look in { { 0, -1 }, { 1, -1 }, { -1, -1 }, { 1, 0 } } do
				local candidate, x, z = choose(mapGround, 0, rootZ, look[1], look[2], DIAMETER)
				T.isTrue(candidate ~= nil, `spot at z {rootZ} look {look[1]},{look[2]}`)
				local radius = DIAMETER / 2
				T.isTrue(z - radius * BallConfig.RecoverySupportShare >= -MAP_EDGE, `supported at z {z}`)
				T.isTrue(math.abs(x) <= MAP_EDGE, "inside in x")
			end
		end
	end)

	test("hole pier: character at the rim facing the hole, the ball is put on the floor", function()
		for _, diameter in { 1.6, 10, DIAMETER } do
			local candidate, x, z = choose(pierGround, 0, -1070, 0, -1, diameter)
			T.isTrue(candidate ~= nil, `spot for diameter {diameter}`)
			T.isTrue(pierGround(x, z) ~= nil, `ground at ({x}, {z})`)
			if diameter == DIAMETER then
				T.isTrue(candidate.bearing ~= 0, "not over the hole in front")
			end
		end
	end)

	test("cliff: ground below the edge is out of reach, the ball stays on the platform", function()
		for _, diameter in { 1.6, 10, DIAMETER } do
			-- 2 studs from the -X edge, facing it.
			local candidate, x, z = choose(cliffGround, -318, -150, -1, 0, diameter)
			T.isTrue(candidate ~= nil, `spot for diameter {diameter}`)
			T.equal(cliffGround(x, z), 70, `on the platform for diameter {diameter}`)
		end
	end)

	test("obstacle clearance: the #34 placement 0.1 stud inside LargeObstacle is rejected", function()
		local radius = 21.3
		T.equal(rules.blocksPlacement(21.2, radius, true), true, "overlapping")
		T.equal(rules.blocksPlacement(radius + 0.2, radius, true), true, "inside the contact margin")
		local clear = radius + BallConfig.RecoveryObstacleClearance
		T.equal(rules.blocksPlacement(clear, radius, true), false, "at the clearance")
		-- At the clearance the first sample sees no contact, so placing never starts a collision.
		T.equal(obstacleRules.isTouching(clear, radius), false)
	end)

	test("other parts: resting on the ground is fine, reaching into a wall is not", function()
		T.equal(rules.blocksPlacement(10, 10, false), false, "ground at the radius")
		T.equal(rules.blocksPlacement(10 - BallConfig.RecoveryPenetrationTolerance / 2, 10, false), false)
		T.equal(rules.blocksPlacement(9.5, 10, false), true, "half a stud into a wall")
	end)

	test("burst bound: run A's burst is cut, a ball pushed off an edge by hand is not (see RecoveryLoop)", function()
		-- Run A: 5 recoveries in about 2 s. With the old rule they would go on as long as the
		-- character stood there; the bound parks the ball at the next one past the limit.
		local times: { number } = {}
		local boundAt = nil
		for index, now in { 0, 1.13, 1.6, 2.0, 2.3, 2.6 } do
			times = rules.recentRecoveries(times, now)
			if rules.atBound(#times) and boundAt == nil then
				boundAt = index
			end
			table.insert(times, now)
		end
		T.equal(boundAt, BallConfig.RecoveryBurstLimit + 1, "parked at the first recovery past the limit")

		-- By hand at diameter 50: about 3 s swing back in front plus 1 s fall per round.
		times = {}
		for round = 0, 10 do
			local now = round * 4
			times = rules.recentRecoveries(times, now)
			T.equal(rules.atBound(#times), false, `round {round}`)
			table.insert(times, now)
		end
	end)

	test("bound: old recoveries leave the window", function()
		local window = BallConfig.RecoveryBurstWindow
		local times = rules.recentRecoveries({ 0, 1, window + 0.5 }, window + 1)
		T.equal(#times, 1)
		T.equal(times[1], window + 0.5)
	end)

	test("grace: shorter than a real fall from the ground to ResetBelowY", function()
		local fall = math.sqrt(2 * -BallConfig.ResetBelowY / GRAVITY)
		T.isTrue(BallConfig.RecoveryGraceTime < fall, `grace {BallConfig.RecoveryGraceTime} < fall {fall}`)
		T.equal(rules.inGrace(10.2, 10), true)
		T.equal(rules.inGrace(10 + BallConfig.RecoveryGraceTime, 10), false)
	end)

	test("stuck: held behind an obstacle out of range is put back within StuckTime", function()
		local dt = BallConfig.SampleInterval
		local tracker: any = nil
		local stuckAfter = nil
		for sample = 1, 200 do
			-- Pressed against the obstacle: jitters by a few tenths, distance about the same.
			local jitter = (sample % 3) * 0.2
			local stuck
			tracker, stuck = rules.stuckStep(tracker, {
				inRange = false,
				distance = 36 + jitter,
				x = 20.9 + jitter,
				z = -35.7,
				elapsed = dt,
			})
			if stuck then
				stuckAfter = sample * dt
				break
			end
		end
		T.isTrue(stuckAfter ~= nil, "put back")
		T.isTrue(
			(stuckAfter :: number) <= BallConfig.StuckTime + 2 * dt,
			`within StuckTime plus a sample: {stuckAfter}`
		)
	end)

	test("stuck: in range, chasing, swinging round or coming closer never counts", function()
		local dt = BallConfig.SampleInterval
		local tracker: any = nil
		local stuck = false
		-- Chasing a character that walks away, out of range the whole time.
		for sample = 1, 300 do
			tracker, stuck = rules.stuckStep(tracker, {
				inRange = false,
				distance = 40,
				x = 0,
				z = -sample * dt * BallConfig.WalkSpeed,
				elapsed = dt,
			})
			T.equal(stuck, false, `chase sample {sample}`)
		end
		-- Swinging round at the same distance (orbit at a quarter of the walk speed).
		tracker = nil
		for sample = 1, 300 do
			local angle = sample * dt * 0.15
			tracker, stuck = rules.stuckStep(tracker, {
				inRange = false,
				distance = 30,
				x = 30 * math.cos(angle),
				z = 30 * math.sin(angle),
				elapsed = dt,
			})
			T.equal(stuck, false, `swing sample {sample}`)
		end
		-- Standing still next to the ball, in range.
		tracker = nil
		for _ = 1, 300 do
			tracker, stuck = rules.stuckStep(tracker, { inRange = true, distance = 27, x = 0, z = 0, elapsed = dt })
			T.equal(stuck, false, "in range")
			T.equal(tracker, nil, "no timer in range")
		end
	end)

	test("stuck: a short moment in range starts the timer over", function()
		local dt = BallConfig.SampleInterval
		local tracker: any = nil
		local stuck = false
		local samples = math.floor(BallConfig.StuckTime / dt) - 2
		for _ = 1, samples do
			tracker, stuck = rules.stuckStep(tracker, { inRange = false, distance = 36, x = 0, z = 0, elapsed = dt })
		end
		T.equal(stuck, false)
		tracker, stuck = rules.stuckStep(tracker, { inRange = true, distance = 27, x = 0, z = 0, elapsed = dt })
		T.equal(tracker, nil)
		for _ = 1, samples do
			tracker, stuck = rules.stuckStep(tracker, { inRange = false, distance = 36, x = 0, z = 0, elapsed = dt })
		end
		T.equal(stuck, false, "the timer started over")
	end)
end)

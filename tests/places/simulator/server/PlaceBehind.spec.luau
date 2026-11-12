--!strict
-- Studio switch BallPlaceBehindObstacle (issue #94 AC8 testability, ADR 0002 "Playtest
-- hooks"): the ball ends just clear of the obstacle's far side, out of growth range, inside the
-- leash, so the stuck rule (not the leash) puts it back. Geometry of LargeObstacle (8-stud
-- cube at (20, 4, -30) on flat ground) with the character 3 studs in front of it, as in the
-- AC9 run (character at about (20, 3, -23)).

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local E = require("../../../helpers/Economy")
local BallCore = require("../../../../src/places/simulator/server/BallService/BallCore")
local GrowthRules = require("../../../../src/places/simulator/server/BallService/GrowthRules")
local ObstacleRules = require("../../../../src/places/simulator/server/BallService/ObstacleRules")
local PlaceBehind = require("../../../../src/places/simulator/server/BallService/PlaceBehind")
local RecoveryRules = require("../../../../src/places/simulator/server/BallService/RecoveryRules")

local core = BallCore.new(BallConfig :: any, E.Config.Zones :: any, E.Zones.zoneOptics)
local growthRules = GrowthRules.new(BallConfig :: any, function(_zone: number): number
	return 1
end)
local obstacleRules = ObstacleRules.new(BallConfig :: any)
local rules = RecoveryRules.new(BallConfig :: any)

local HALF = 4 -- LargeObstacle is 8 x 8 x 8, centre 4 above the ground
local GAP_TO_FACE = 3 -- character root 3 studs in front of the near face
local ROOT_HEIGHT = 3
local STEP = 0.25

-- Ball centre distance behind the obstacle centre, and the facts the server then sees.
local function place(diameter: number)
	local radius = diameter / 2
	local clear = radius + BallConfig.RecoveryObstacleClearance
	-- Line along +Z from the obstacle centre; ball centre `radius` above flat ground.
	local t = PlaceBehind.clearDistance(function(distanceT: number): number?
		return obstacleRules.boxDistance(0, radius - HALF, distanceT, HALF, HALF, HALF)
	end, clear, STEP, 2 * HALF + clear + 1)
	local horizontal = (t :: number) + HALF + GAP_TO_FACE
	return t, horizontal, radius
end

return T.suite("Simulator BallPlaceBehindObstacle (#94 AC8)", function(test)
	test("clearDistance: first step that is clear, nil when none or no ground", function()
		T.equal(
			PlaceBehind.clearDistance(function(t: number): number?
				return t
			end, 2, 0.5, 10),
			2
		)
		T.equal(
			PlaceBehind.clearDistance(function(_t: number): number?
				return 0
			end, 2, 0.5, 10),
			nil
		)
		T.equal(
			PlaceBehind.clearDistance(function(t: number): number?
				return if t < 5 then nil else t
			end, 2, 0.5, 10),
			5,
			"no ground near the obstacle"
		)
	end)

	for _, fraction in { 0.5, 0.75 } do
		test(`zone 50 fraction {fraction}: just clear, out of growth range, inside the leash, then stuck`, function()
			local diameter = core.visualDiameter(50, fraction)
			local t, horizontal, radius = place(diameter)
			T.isTrue(t ~= nil, "a spot")
			local gap = obstacleRules.boxDistance(0, radius - HALF, t :: number, HALF, HALF, HALF) - radius
			T.isTrue(gap >= BallConfig.RecoveryObstacleClearance, `gap {gap}`)
			T.isTrue(gap < BallConfig.RecoveryObstacleClearance + STEP + 0.01, `just clear: {gap}`)
			local vertical = ROOT_HEIGHT - radius
			T.equal(growthRules.inGrowthRange(horizontal, vertical, diameter), false, "out of growth range")
			T.equal(rules.heldOnSlope(horizontal, 0, 0, diameter), false, "not held on a slope either")
			T.equal(core.isOutOfReach(horizontal, diameter), false, "inside the leash")
			-- Pressed into the obstacle it moves less than StuckProgressStuds: stuck after StuckTime.
			local tracker: any = nil
			local stuckAt = nil
			for sample = 1, 100 do
				local stuck
				tracker, stuck = rules.stuckStep(tracker, {
					inRange = false,
					distance = horizontal - math.min(sample, 5) * 0.1,
					x = 0,
					z = horizontal - math.min(sample, 5) * 0.1,
					elapsed = BallConfig.SampleInterval,
				})
				if stuck then
					stuckAt = sample * BallConfig.SampleInterval
					break
				end
			end
			T.isTrue(stuckAt ~= nil and stuckAt <= BallConfig.StuckTime + 0.2, `stuck at {stuckAt}`)
		end)
	end

	test("the full-size ball (fraction 1) ends inside the growth range: use 0.5 or 0.75", function()
		local diameter = core.visualDiameter(50, 1)
		local _, horizontal, radius = place(diameter)
		T.equal(growthRules.inGrowthRange(horizontal, ROOT_HEIGHT - radius, diameter), true)
	end)
end)

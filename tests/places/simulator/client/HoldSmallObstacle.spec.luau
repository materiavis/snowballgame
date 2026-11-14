--!strict
-- HoldMath at the 1-stud SmallObstacle the character steps over (issue #97 round 4, AC2,
-- ADR 0002 "After a hit"), on the 2D model in helpers/ObstacleModel with `characterPassesBox`.
-- Owner decisions on #97 round 4: the ball gets past with the character within 4.5 studs and
-- `outFor` ≤ ReboundMaxSecondsSmallObstacle (1.5 s) in the approach model (d1); after the
-- step-over (d2) no ball may still be out at the end of the watch (no hang), and the 4.5/1.5
-- limit there is judged in Studio, because this model is harsher than Studio (main fails most
-- d2 cases here and passed all six runs in Studio: the 2D cube is a wall of any height, the
-- ball cannot ride over its edge).

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")
local HoldMathMain = require("./fixtures/HoldMathMain")
local ObstacleModel = require("../../../helpers/ObstacleModel")

-- SmallObstacle of the placeholder map: 1 × 1 × 1 at (-20, 0.5, -30).
local SMALL = { x0 = -20.5, x1 = -19.5, z0 = -30.5, z1 = -29.5 }
local CUBE_TOP = 1
-- Zone 1 fraction 0 and 0.5.
local DIAMETERS = { 1.6, 2.8 }
local BALL_OFFSETS = { 0, 0.5, -0.5, 1.3, -1.3 }

local current = HoldMath.new(BallConfig :: any)
local main = HoldMathMain.new(BallConfig :: any)

-- Horizontal contact radius on the cube: a ball whose centre is above the cube's top touches
-- its top edge.
local function contactRadius(diameter: number): number
	local radius = diameter / 2
	if radius <= CUBE_TOP then
		return radius
	end
	return math.sqrt(radius ^ 2 - (radius - CUBE_TOP) ^ 2)
end

-- d1: the ball held in front, the character walks -Z from z -10 into the cube, its body
-- sliding round the ball, for 3 s, then stands 3 s.
local function approach(kind: string, diameter: number, offset: number, side: number): ObstacleModel.Result
	local hold: any = if kind == "main" then main else current
	local x = -20 + offset
	return ObstacleModel.run({
		hold = hold,
		kind = kind,
		config = BallConfig,
		box = SMALL,
		diameter = diameter,
		contactRadius = contactRadius(diameter),
		characterX = x + side,
		characterZ = -10,
		ballX = x,
		ballZ = -10 - hold.holdDistance(diameter),
		walkX = 0,
		walkZ = -1,
		walkSeconds = 3,
		standSeconds = 3,
		characterPassesBox = true,
	})
end

-- d2: the state the round-3 playtest saw: the character has stepped over the cube, the ball
-- rests against its +Z face behind the character; the character walks on 2 s, then stands 3 s.
local function afterStepOver(kind: string, diameter: number, offset: number, side: number): ObstacleModel.Result
	local hold: any = if kind == "main" then main else current
	local contact = contactRadius(diameter)
	local bx = -20 + offset
	local beside = math.max(math.abs(offset) - 0.5, 0)
	local bz = SMALL.z1 + math.sqrt(math.max(contact ^ 2 - beside ^ 2, 0)) + 0.05
	return ObstacleModel.run({
		hold = hold,
		kind = kind,
		config = BallConfig,
		box = SMALL,
		diameter = diameter,
		contactRadius = contact,
		characterX = bx + side,
		characterZ = bz - hold.holdDistance(diameter),
		ballX = bx,
		ballZ = bz,
		walkX = 0,
		walkZ = -1,
		walkSeconds = 2,
		standSeconds = 3,
		characterPassesBox = true,
	})
end

local function past(result: ObstacleModel.Result): boolean
	return result.ballZ < SMALL.z0 and not result.outAtEnd
end

return T.suite("Simulator HoldMath at the SmallObstacle (#97 round 4)", function(test)
	test("the contact hold ends only walking, with the ball beyond HoldContactReleaseDegrees", function()
		local function at(degrees: number): (number, number)
			return math.sin(math.rad(degrees)) * 3, -math.cos(math.rad(degrees)) * 3
		end
		-- Walking -Z, a ball 95° off (squeezed to just behind the side) keeps the contact hold.
		local sx, sz = at(95)
		local hx, hz = current.nextHeldDirection(0, -1, 0, -1, sx, sz, false, true)
		T.near(hx, sx / 3, 1e-9)
		T.near(hz, sz / 3, 1e-9)
		-- Beyond the release angle walking steers, as on main.
		local bx, bz = at(BallConfig.HoldContactReleaseDegrees + 1)
		hx, hz = current.nextHeldDirection(0, -1, 0, -1, bx, bz, false, true)
		T.equal(hx, 0)
		T.equal(hz, -1)
		-- Standing, even a ball straight behind keeps the contact hold (round 3).
		hx, hz = current.nextHeldDirection(0, -1, 0, 0, 0, 3, false, true)
		T.equal(hx, 0)
		T.equal(hz, 1)
	end)

	test("d1: walking over the cube, the ball gets past with the character inside the limit", function()
		for _, diameter in DIAMETERS do
			for _, offset in BALL_OFFSETS do
				for _, side in { 0.2, -0.2, 0.6 } do
					local result = approach("new", diameter, offset, side)
					local label =
						`diameter {diameter} offset {offset} side {side}: {result.most} studs, out {result.outFor} s`
					T.isTrue(past(result), `{label}: past the cube`)
					T.isTrue(result.most <= BallConfig.ReboundMaxStuds, label)
					T.isTrue(result.outFor <= BallConfig.ReboundMaxSecondsSmallObstacle, label)
				end
			end
		end
	end)

	test("d2 cause: with the round-3 contact hold behind the character the ball hangs", function()
		-- Round 3 kept the hold on the ball's bearing whatever the angle; the release angle
		-- above 180° switches that off.
		local config = table.clone(BallConfig) :: any
		config.HoldContactReleaseDegrees = 181
		local saved = current
		current = HoldMath.new(config)
		local result = afterStepOver("new", 1.6, 0, 0)
		current = saved
		T.isTrue(result.outAtEnd, `still out at the end: {result.most} studs`)
	end)

	test("d2: after the step-over no ball hangs at the cube", function()
		for _, diameter in DIAMETERS do
			for _, offset in BALL_OFFSETS do
				for _, side in { 0, 0.3, -0.3 } do
					local result = afterStepOver("new", diameter, offset, side)
					local label =
						`diameter {diameter} offset {offset} side {side}: {result.most} studs, out {result.outFor} s`
					T.isTrue(past(result), `{label}: past the cube, not out at the end`)
					T.isTrue(result.most < BallConfig.LeashDistance, `{label}: no leash recovery`)
				end
			end
		end
	end)
end)

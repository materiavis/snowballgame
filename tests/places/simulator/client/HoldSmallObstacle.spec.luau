--!strict
-- HoldMath at the 1-stud SmallObstacle the character steps over (issue #97 rounds 4 and 5, AC2,
-- ADR 0002 "After a hit"), on the 2D model in helpers/ObstacleModel with `characterPassesBox`.
-- Round 5 (owner decision): the contact hold applies only to obstacles that cannot be knocked
-- over, so a ball touching only SmallObstacle (it has KnockOverSize) gets main's hold direction;
-- the touch still arms the approach limit and the rebound brake. d1 is the approach (the ball
-- held in front, the character walks into the cube), d2 the state the round-3 playtest saw
-- (character past the cube, ball against it behind him). The limit (4.5 studs, `outFor` ≤
-- ReboundMaxSecondsSmallObstacle) is judged in Studio; this model is harsher than Studio (main
-- fails most d2 cases here and passed all six Studio runs: the 2D cube is a wall of any height,
-- the ball cannot ride over its edge). The specs here check the hold direction and that no ball
-- hangs at the cube.

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

-- The current hold, recording for every frame whether its hold direction differs from main's
-- for the same inputs.
local function recording(): (any, () -> number)
	local wrapped = table.clone(current) :: any
	local differing = 0
	wrapped.nextHeldDirection = function(hx, hz, mx, mz, rx, rz, follow, touching)
		local x, z = current.nextHeldDirection(hx, hz, mx, mz, rx, rz, follow, touching)
		local mainX, mainZ = main.nextHeldDirection(hx, hz, mx, mz, rx, rz, follow)
		if math.abs(x - mainX) > 1e-12 or math.abs(z - mainZ) > 1e-12 then
			differing += 1
		end
		return x, z
	end
	return wrapped, function()
		return differing
	end
end

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
local function approach(hold: any, kind: string, diameter: number, offset: number, side: number): ObstacleModel.Result
	local x = -20 + offset
	return ObstacleModel.run({
		hold = hold,
		kind = kind,
		config = BallConfig,
		box = SMALL,
		knockOver = true,
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

-- d2: the character has stepped over the cube, the ball rests against its +Z face behind him;
-- he walks on 2 s, then stands 3 s. `knockOver` false is round 3/4's contact hold at this cube.
local function afterStepOver(
	hold: any,
	kind: string,
	diameter: number,
	offset: number,
	side: number,
	knockOver: boolean
): ObstacleModel.Result
	local contact = contactRadius(diameter)
	local bx = -20 + offset
	local beside = math.max(math.abs(offset) - 0.5, 0)
	local bz = SMALL.z1 + math.sqrt(math.max(contact ^ 2 - beside ^ 2, 0)) + 0.05
	return ObstacleModel.run({
		hold = hold,
		kind = kind,
		config = BallConfig,
		box = SMALL,
		knockOver = knockOver,
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

return T.suite("Simulator HoldMath at the SmallObstacle (#97 rounds 4 and 5)", function(test)
	test("c: a ball touching only a knock-over-able obstacle gets main's hold direction every frame", function()
		local touchedCases = 0
		for _, diameter in DIAMETERS do
			for _, offset in BALL_OFFSETS do
				for _, side in { 0.2, -0.2, 0.6 } do
					local hold, differing = recording()
					local result = approach(hold, "new", diameter, offset, side)
					T.equal(differing(), 0, `d1 diameter {diameter} offset {offset} side {side}`)
					if result.touched then
						touchedCases += 1
						T.equal(result.armedAtTouch, true, "the touch still arms the brake")
					end
				end
				for _, side in { 0, 0.3, -0.3 } do
					local hold, differing = recording()
					afterStepOver(hold, "new", diameter, offset, side, true)
					T.equal(differing(), 0, `d2 diameter {diameter} offset {offset} side {side}`)
				end
			end
		end
		T.isTrue(touchedCases > 0, "the approach touches the cube")
	end)

	test("d1: walking over the cube, the ball gets past with the character", function()
		for _, diameter in DIAMETERS do
			for _, offset in BALL_OFFSETS do
				for _, side in { 0.2, -0.2, 0.6 } do
					local result = approach(current, "new", diameter, offset, side)
					local label =
						`diameter {diameter} offset {offset} side {side}: {result.most} studs, out {result.outFor} s`
					T.isTrue(past(result), `{label}: past the cube, not out at the end`)
					T.isTrue(result.most < BallConfig.LeashDistance, `{label}: no leash recovery`)
				end
			end
		end
	end)

	test("d2 cause: with the contact hold at the cube the ball hangs behind the character", function()
		local result = afterStepOver(current, "new", 1.6, 0, 0, false)
		T.isTrue(result.outAtEnd, `still out at the end: {result.most} studs`)
	end)

	test("d2: after the step-over no ball hangs at the cube", function()
		for _, diameter in DIAMETERS do
			for _, offset in BALL_OFFSETS do
				for _, side in { 0, 0.3, -0.3 } do
					local result = afterStepOver(current, "new", diameter, offset, side, true)
					local label =
						`diameter {diameter} offset {offset} side {side}: {result.most} studs, out {result.outFor} s`
					T.isTrue(past(result), `{label}: past the cube, not out at the end`)
					T.isTrue(result.most < BallConfig.LeashDistance, `{label}: no leash recovery`)
				end
			end
		end
	end)
end)

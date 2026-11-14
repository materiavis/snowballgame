--!strict
-- HoldMath against an obstacle box (issue #97, ADR 0002 "After a hit"), on the 2D model in
-- helpers/ObstacleModel. Owner decision after round 2: the off-centre sweep is judged without
-- contact friction, the ball held behind the obstacle (#94 AC8) with friction 0.45 (Roblox's
-- weighted mean of the ball's 0.6 and Plastic's 0.3; the obstacle's material is an
-- assumption). `fixtures/HoldMathMain` is the hold exactly as on main before #97.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")
local HoldMathMain = require("./fixtures/HoldMathMain")
local ObstacleModel = require("../../../helpers/ObstacleModel")

-- LargeObstacle of the placeholder map: 8 × 8 × 8 at (20, 4, -30).
local LARGE = { x0 = 16, x1 = 24, z0 = -34, z1 = -26 }
local AC8_FRICTION = 0.45

local current = HoldMath.new(BallConfig :: any)
local main = HoldMathMain.new(BallConfig :: any)

local function length(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

-- The character walks from z -10 at `angle` degrees off -Z into the +Z face, then stands.
local function push(kind: string, startX: number, angle: number, walkSeconds: number): ObstacleModel.Result
	local hold: any = if kind == "main" then main else current
	local wx, wz = math.sin(math.rad(angle)), -math.cos(math.rad(angle))
	local distance = hold.holdDistance(4)
	return ObstacleModel.run({
		hold = hold,
		kind = kind,
		config = BallConfig,
		box = LARGE,
		diameter = 4,
		characterX = startX,
		characterZ = -10,
		ballX = startX + wx * distance,
		ballZ = -10 + wz * distance,
		walkX = wx,
		walkZ = wz,
		walkSeconds = walkSeconds,
		standSeconds = 3.5,
	})
end

local function withinLimit(result: ObstacleModel.Result): boolean
	return result.most <= BallConfig.ReboundMaxStuds
		and result.outFor <= BallConfig.ReboundMaxSeconds
		and not result.outAtEnd
end

-- #94 AC8: the 35-stud ball put 0.59 studs (horizontal; 0.5 in 3D) behind LargeObstacle on the
-- line from the character through its centre. The ball touches the cube's top edge, so its
-- horizontal contact radius is √(17.5² - 9.5²). The character stands 3 studs before the +Z face,
-- `lateral` studs off the centre line; the hold follows the ball for RecoveryHoldResetTime.
local function behind(kind: string, lateral: number): number
	local hold: any = if kind == "main" then main else current
	local contact = math.sqrt(17.5 ^ 2 - 9.5 ^ 2)
	local cx, cz = 20 + lateral, -23
	local dx, dz = 20 - cx, -30 - cz
	local l = length(dx, dz)
	dx, dz = dx / l, dz / l
	local t, bx, bz = 0, 20, -30
	repeat
		t += 0.05
		bx, bz = 20 + dx * t, -30 + dz * t
		local gap = length(bx - math.clamp(bx, 16, 24), bz - math.clamp(bz, -34, -26)) - contact
	until gap >= 0.59
	return ObstacleModel.run({
		hold = hold,
		kind = kind,
		config = BallConfig,
		box = LARGE,
		diameter = 35,
		contactRadius = contact,
		characterX = cx,
		characterZ = cz,
		ballX = bx,
		ballZ = bz,
		walkX = dx,
		walkZ = dz,
		walkSeconds = 0,
		standSeconds = 4.5,
		followSeconds = BallConfig.RecoveryHoldResetTime,
		friction = AC8_FRICTION,
	}).moved
end

return T.suite("Simulator HoldMath against an obstacle box (#97)", function(test)
	test("cause: main's hold drives a ball pressed on the face along it and round the corner", function()
		local result = push("main", 22, -5, 2.5)
		T.isTrue(result.most > BallConfig.ReboundMaxStuds, `{result.most} studs out`)
		T.isTrue(result.outAtEnd, "still out when the watch ends")
	end)

	test("c: off-centre and at an angle, pushing on and then standing stays inside the limit", function()
		for _, angle in { -10, -5, 0, 5, 10, 20 } do
			for _, startX in { 22, 20, 18, 16, 15, 14.5 } do
				for _, walkSeconds in { 2.5, 4 } do
					local result = push("new", startX, angle, walkSeconds)
					local label =
						`angle {angle} x {startX} walk {walkSeconds} s: {result.most} studs, out {result.outFor} s`
					T.isTrue(withinLimit(result), label)
				end
			end
		end
	end)

	test("c: walking on along the face and past the corner stays inside the limit", function()
		for _, angle in { -10, -5, 0, 5, 10, 20 } do
			for _, startX in { 22, 20, 18, 16, 15, 14.5 } do
				local result = push("new", startX, angle, 6)
				T.isTrue(withinLimit(result), `angle {angle} x {startX}: {result.most} studs, out {result.outFor} s`)
			end
		end
	end)

	test("b (R3): the ball held behind the obstacle moves less than 2 studs and no more than on main", function()
		for _, lateral in { 0, 1, 2 } do
			local now, before = behind("new", lateral), behind("main", lateral)
			T.isTrue(now < BallConfig.StuckProgressStuds, `lateral {lateral}: moved {now}`)
			T.isTrue(now <= before + 0.05, `lateral {lateral}: {now} against main {before}`)
		end
	end)

	test("a pressed ball is pushed no harder than HoldMaxAcceleration, even when it jitters (R3)", function()
		-- Round 0 let a tiny outward speed unlock the unclamped command (about 370).
		local distance = current.holdDistance(35)
		local rz = -(distance + 8)
		local wantX, wantZ = current.desiredVelocity(0, rz, 0, -1, distance, 0, 0, BallConfig.WalkSpeed)
		for _, jitter in { 0, 0.01, 0.5, 3 } do
			local ax, az, braking = current.holdAcceleration(wantX, wantZ, 0, -jitter, 0, rz, 0, 0, distance)
			T.isTrue(length(ax, az) <= BallConfig.HoldMaxAcceleration + 1e-9, `jitter {jitter}: {length(ax, az)}`)
			T.equal(braking, false, `jitter {jitter}`)
		end
	end)
end)

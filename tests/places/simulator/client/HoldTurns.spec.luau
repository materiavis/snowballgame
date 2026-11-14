--!strict
-- Free-field turns against main (issue #97, owner decision after round 2: "not slower than
-- main, at most +0.05 s"). `fixtures/HoldMathMain` is BallController/HoldMath exactly as on main
-- at 2746a6d, driven like main's controller (no contact flag, plain `acceleration`); the
-- current HoldMath is driven like the current controller (`holdAcceleration`, no obstacle).
--
-- Model: the character walks -Z at WalkSpeed with the ball held in front, then walks the new
-- direction at once. Rolling ball (5/7 of the force becomes speed), physics at 240 Hz with the
-- force of the frame. Measured: seconds until the ball is within 15° of the new walking
-- direction and within 1 stud of the hold distance. The model's absolute times are not Studio
-- times; only the comparison counts.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")
local HoldMathMain = require("./fixtures/HoldMathMain")

local ROLLING = 5 / 7
local WALK = BallConfig.WalkSpeed
local SETTLED_DEGREES = 15
local SETTLED_STUDS = 1
local TOLERANCE = 0.05

local main = HoldMathMain.new(BallConfig :: any)
local current = HoldMath.new(BallConfig :: any)

local function turnTime(isMain: boolean, diameter: number, toX: number, toZ: number, fps: number): number
	local hold: any = if isMain then main else current
	local distance = hold.holdDistance(diameter)
	local cx, cz = 0, 0
	local bx, bz, bvx, bvz = 0, -distance, 0, -WALK
	local hx, hz = 0, -1
	local dx, dz = 0, -1
	local turnedAt: number? = nil
	for frame = 1, 10 * fps do
		local now = frame / fps
		if now > 2 and turnedAt == nil then
			dx, dz = toX, toZ
			turnedAt = now
		end
		local cvx, cvz = dx * WALK, dz * WALK
		local rx, rz = bx - cx, bz - cz
		local ax, az
		if isMain then
			hx, hz = hold.nextHeldDirection(hx, hz, dx, dz, rx, rz, false)
			local wantX, wantZ = hold.desiredVelocity(rx, rz, hx, hz, distance, cvx, cvz, WALK)
			ax, az = hold.acceleration(wantX, wantZ, bvx, bvz)
		else
			hx, hz = hold.nextHeldDirection(hx, hz, dx, dz, rx, rz, false, false)
			local wantX, wantZ = hold.desiredVelocity(rx, rz, hx, hz, distance, cvx, cvz, WALK)
			ax, az = hold.holdAcceleration(wantX, wantZ, bvx, bvz, rx, rz, cvx, cvz, distance)
		end
		for _ = 1, 240 // fps do
			cx += cvx / 240
			cz += cvz / 240
			bvx += ax * ROLLING / 240
			bvz += az * ROLLING / 240
			bx += bvx / 240
			bz += bvz / 240
		end
		if turnedAt ~= nil and now > turnedAt then
			local ox, oz = bx - cx, bz - cz
			local l = math.sqrt(ox * ox + oz * oz)
			local angle = math.deg(math.acos(math.clamp((ox * dx + oz * dz) / l, -1, 1)))
			if angle <= SETTLED_DEGREES and math.abs(l - distance) <= SETTLED_STUDS then
				return now - turnedAt
			end
		end
	end
	return math.huge
end

return T.suite("Simulator hold turns against main (#97, R5)", function(test)
	test("90° and 180°, small and large ball, 60 and 30 fps: never slower than main", function()
		for _, fps in { 60, 30 } do
			-- Zone 1 fraction 0.5 (hold 2.9) and the 50-stud Visual Cap ball (hold 26.5).
			for _, diameter in { 2.8, 50 } do
				for _, turn in { { 1, 0, 90 }, { 0, 1, 180 } } do
					local before = turnTime(true, diameter, turn[1], turn[2], fps)
					local now = turnTime(false, diameter, turn[1], turn[2], fps)
					local label = `{fps} fps diameter {diameter} {turn[3]}°: main {before} s, now {now} s`
					T.isTrue(before < math.huge, `{label}: main settles`)
					T.isTrue(now <= before + TOLERANCE, label)
				end
			end
		end
	end)

	test("the fixture is main: with the #97 parts switched off the current hold turns exactly like it", function()
		-- No rebound brake (its limit 0 never beats HoldMaxAcceleration), no approach limit.
		local off = table.clone(BallConfig) :: any
		off.HoldReboundMaxAcceleration = 0
		off.HoldApproachDeceleration = 1e12
		local saved = current
		current = HoldMath.new(off)
		for _, turn in { { 1, 0 }, { 0, 1 } } do
			for _, diameter in { 2.8, 50 } do
				T.near(
					turnTime(false, diameter, turn[1], turn[2], 60),
					turnTime(true, diameter, turn[1], turn[2], 60),
					1e-9
				)
			end
		end
		current = saved
	end)
end)

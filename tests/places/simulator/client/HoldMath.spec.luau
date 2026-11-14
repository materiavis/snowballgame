--!strict
-- HoldMath (issue #33 AC1, ADR 0002): the ball swings to every new walking direction around
-- the character (not through it), a big ball swings slower, and the ball keeps pace at any
-- walk speed. A small 2D simulation stands in for Roblox physics.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local E = require("../../../helpers/Economy")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")
local BallCore = require("../../../../src/places/simulator/server/BallService/BallCore")

local hold = HoldMath.new(BallConfig :: any)
local DT = 1 / 60
local ROOT_HALF_DEPTH = 0.5 -- HumanoidRootPart is 2 x 2 x 1 studs

local function length(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

-- Character position c, ball position b and velocity bv, unit hold direction h (all x/z).
type Sim = {
	cx: number,
	cz: number,
	bx: number,
	bz: number,
	bvx: number,
	bvz: number,
	hx: number,
	hz: number,
}

local function newSim(diameter: number): Sim
	local distance = hold.holdDistance(diameter)
	return { cx = 0, cz = 0, bx = 0, bz = -distance, bvx = 0, bvz = 0, hx = 0, hz = -1 }
end

-- Same order as BallController: the hold direction is the walking direction while moving,
-- and the controller reads both bodies before the physics step moves them.
local function stepSim(sim: Sim, diameter: number, dx: number, dz: number, walkSpeed: number, dt: number?)
	local step = dt or DT
	local distance = hold.holdDistance(diameter)
	local moving = length(dx, dz) > BallConfig.MoveDeadzone
	if moving then
		sim.hx, sim.hz = dx, dz
	end
	local cvx, cvz = if moving then dx * walkSpeed else 0, if moving then dz * walkSpeed else 0
	local wantX, wantZ =
		hold.desiredVelocity(sim.bx - sim.cx, sim.bz - sim.cz, sim.hx, sim.hz, distance, cvx, cvz, walkSpeed)
	local ax, az =
		hold.holdAcceleration(wantX, wantZ, sim.bvx, sim.bvz, sim.bx - sim.cx, sim.bz - sim.cz, cvx, cvz, distance)
	sim.cx += cvx * step
	sim.cz += cvz * step
	sim.bvx += ax * step
	sim.bvz += az * step
	sim.bx += sim.bvx * step
	sim.bz += sim.bvz * step
end

-- Angle between the walking direction and the direction from character to ball, degrees.
local function frontError(sim: Sim, dx: number, dz: number): number
	local ox, oz = sim.bx - sim.cx, sim.bz - sim.cz
	local l = length(ox, oz)
	local cosine = math.clamp((ox * dx + oz * dz) / l, -1, 1)
	return math.deg(math.acos(cosine))
end

return T.suite("Simulator HoldMath (7.3)", function(test)
	test("hold distance matches the server's (spawn, leash) for every size", function()
		local core = BallCore.new(BallConfig :: any, E.Config.Zones :: any, E.Zones.zoneOptics)
		for _, diameter in { 1.6, 4, 12.3, 50 } do
			T.equal(hold.holdDistance(diameter), core.holdDistance(diameter), `diameter {diameter}`)
		end
	end)

	test("a big ball swings slower: orbit speed and centripetal limits", function()
		local walkSpeed = BallConfig.WalkSpeed
		local previous = math.huge
		for _, diameter in { 1.6, 4, 20, 50 } do
			local distance = hold.holdDistance(diameter)
			local rate = hold.maxOrbitRate(distance, walkSpeed)
			T.isTrue(rate <= math.rad(BallConfig.HoldTurnRateDegrees) + 1e-9, `{diameter} turn rate`)
			T.isTrue(rate < previous, `{diameter} slower than a smaller ball`)
			previous = rate
			T.isTrue(rate * distance <= BallConfig.HoldMaxOrbitSpeedFactor * walkSpeed + 1e-9, `{diameter} speed`)
			local centripetal = rate * rate * distance
			T.isTrue(
				centripetal <= BallConfig.HoldCentripetalShare * BallConfig.HoldMaxAcceleration + 1e-9,
				`{diameter} centripetal`
			)
		end
	end)

	test("velocity and acceleration are limited", function()
		local wantX, wantZ = hold.desiredVelocity(1e6, 0, 0, -1, 3, 0, 0, BallConfig.WalkSpeed)
		T.near(length(wantX, wantZ), BallConfig.HoldMaxSpeedFactor * BallConfig.WalkSpeed, 1e-6, "far ball")
		local ax, az = hold.acceleration(1e6, 0, 0, 0)
		T.near(length(ax, az), BallConfig.HoldMaxAcceleration, 1e-6, "acceleration")
		wantX, wantZ = hold.desiredVelocity(0, -3, 0, -1, 3, 0, 0, BallConfig.WalkSpeed)
		T.near(length(wantX, wantZ), 0, 1e-9, "at the hold point and standing")
	end)

	test("a ball on top of the character is pushed out along the hold direction", function()
		local wantX, wantZ = hold.desiredVelocity(0, 0, 1, 0, 3, 0, 0, BallConfig.WalkSpeed)
		T.isTrue(wantX > 0 and math.abs(wantZ) < 1e-9)
	end)

	test("AC1: the ball stays in front through every direction change, small and big", function()
		local directions = {
			{ 0, -1 },
			{ 1, 0 },
			{ 0, 1 }, -- reversal
			{ -1, 0 },
			{ math.sqrt(0.5), math.sqrt(0.5) },
			{ 0, -1 },
		}
		-- 60 fps and a slow phone at 30 fps.
		for _, fps in { 60, 30 } do
			for _, diameter in { 1.6, 4, 20, 50 } do
				local sim = newSim(diameter)
				local label = `{fps} fps diameter {diameter}`
				for _, direction in directions do
					local dx, dz = direction[1], direction[2]
					local closest = math.huge
					for _ = 1, 4 * fps do
						stepSim(sim, diameter, dx, dz, BallConfig.WalkSpeed, 1 / fps)
						closest = math.min(closest, length(sim.bx - sim.cx, sim.bz - sim.cz))
					end
					-- Swinging around, not through: the surface stays outside the HumanoidRootPart
					-- (half depth ROOT_HALF_DEPTH). Touching the rest of the body is allowed; that is the push.
					T.isTrue(closest > diameter / 2 + ROOT_HALF_DEPTH, `{label} closest {closest}`)
					T.isTrue(frontError(sim, dx, dz) < 5, `{label} in front after turning`)
					local distance = length(sim.bx - sim.cx, sim.bz - sim.cz)
					T.near(distance, hold.holdDistance(diameter), 0.5, `{label} at hold distance`)
				end
			end
		end
	end)

	test("push speed follows walk speed: the ball keeps pace at 16, 32 and 40 studs/s", function()
		for _, walkSpeed in { BallConfig.WalkSpeed, 32, 40 } do
			local sim = newSim(4)
			for _ = 1, 3 * 60 do
				stepSim(sim, 4, 0, -1, walkSpeed)
			end
			T.near(length(sim.bvx, sim.bvz), walkSpeed, 0.1, `ball speed at walk speed {walkSpeed}`)
			T.near(length(sim.bx - sim.cx, sim.bz - sim.cz), hold.holdDistance(4), 0.1, "no lag into the character")
		end
	end)

	test("standing still, the ball comes to rest in front", function()
		local sim = newSim(4)
		for _ = 1, 60 do
			stepSim(sim, 4, 1, 0, BallConfig.WalkSpeed)
		end
		for _ = 1, 3 * 60 do
			stepSim(sim, 4, 0, 0, BallConfig.WalkSpeed)
		end
		T.near(length(sim.bvx, sim.bvz), 0, 0.05, "at rest")
		T.isTrue(frontError(sim, 1, 0) < 1, "still in front")
	end)

	-- #94 round 1: the playtest at f95545a. Character at (196, -1012.3) standing still, facing
	-- the -Z map edge (z -1024, 11.7 studs ahead); the server put the ball back `Around` at
	-- (219, -999). Relative to the character: (23, 13.3). The ball first still shows the fall
	-- position for a few frames, as if the Recoveries attribute arrived before the new position.
	local EDGE_Z = -11.7
	local function afterRecovery(follow: boolean, seconds: number): (Sim, number)
		local diameter = 50
		local sim = newSim(diameter)
		sim.bx, sim.bz = 0, -26.3 -- over the edge, before the put-back arrives
		local recoveredAt = 0
		local lowestZ = math.huge
		for frame = 1, seconds * 60 do
			if frame == 5 then
				sim.bx, sim.bz, sim.bvx, sim.bvz = 23, 13.3, 0, 0
			end
			local now = (frame - 1) * DT
			local followBall = follow and hold.followsBall(now, recoveredAt)
			sim.hx, sim.hz = hold.nextHeldDirection(sim.hx, sim.hz, 0, 0, sim.bx, sim.bz, followBall)
			stepSim(sim, diameter, 0, 0, BallConfig.WalkSpeed)
			if frame >= 5 then
				lowestZ = math.min(lowestZ, sim.bz)
			end
		end
		return sim, lowestZ
	end

	test("#94: without the reset the old hold swings the put-back ball over the edge again", function()
		local _, lowestZ = afterRecovery(false, 10)
		T.isTrue(lowestZ < EDGE_Z, `reaches z {lowestZ} past the edge {EDGE_Z}`)
	end)

	test("#94: after a recovery the hold follows the ball and keeps it where the server put it", function()
		local sim, lowestZ = afterRecovery(true, 10)
		T.isTrue(lowestZ > EDGE_Z, `stays behind the edge: lowest z {lowestZ}`)
		local bearing = math.deg(math.atan2(sim.bz, sim.bx))
		T.near(bearing, math.deg(math.atan2(13.3, 23)), 2, "keeps the put-back bearing")
		T.near(length(sim.bvx, sim.bvz), 0, 0.05, "at rest")
	end)

	test("#94: walking wins over the reset, so walking out over the edge again is a normal push", function()
		local hx, hz = hold.nextHeldDirection(1, 0, 0, -1, 23, 13.3, true)
		T.equal(hx, 0)
		T.equal(hz, -1)
		hx, hz = hold.nextHeldDirection(1, 0, 0.05, 0, 23, 13.3, false)
		T.equal(hx, 1, "below the deadzone the old direction stays")
		T.equal(hz, 0)
	end)

	test("#94: the reset window and the direction fallback", function()
		local window = BallConfig.RecoveryHoldResetTime
		T.equal(hold.followsBall(5, nil), false, "no recovery seen")
		T.equal(hold.followsBall(10 + window / 2, 10), true)
		T.equal(hold.followsBall(10 + window, 10), false)
		local x, z = hold.directionTo(0, 0, 0, -1)
		T.equal(x, 0, "ball on the character: fallback")
		T.equal(z, -1)
		x, z = hold.directionTo(3, 4, 0, -1)
		T.near(x, 0.6, 1e-9)
		T.near(z, 0.8, 1e-9)
	end)

	-- #97: the ball leaves the hold point (pushed off an obstacle or squeezed out) while the
	-- character stands, hold direction -Z. Physics runs at 240 Hz with the force of the last
	-- frame. A rolling solid sphere turns only 5/7 of a force at its centre into speed; an
	-- airborne one all of it. Returns the most studs beyond the hold distance, the last time
	-- it was more than ReboundSettleStuds beyond, and the closest approach (negative = inside).
	local ROLLING = 5 / 7
	local function rebound(
		diameter: number,
		startOffset: number,
		speed: number,
		share: number,
		fps: number,
		brake: boolean
	): (number, number, number)
		local distance = hold.holdDistance(diameter)
		local bx, bz, bvx, bvz = 0, -distance - startOffset, 0, -speed
		local most, closest, lastOut = -math.huge, math.huge, 0
		local substeps = 240 // fps
		for frame = 1, 5 * fps do
			local wantX, wantZ = hold.desiredVelocity(bx, bz, 0, -1, distance, 0, 0, BallConfig.WalkSpeed)
			local ax, az
			if brake then
				ax, az = hold.holdAcceleration(wantX, wantZ, bvx, bvz, bx, bz, 0, 0, distance)
			else
				ax, az = hold.acceleration(wantX, wantZ, bvx, bvz)
			end
			for _ = 1, substeps do
				bvx += ax * share / 240
				bvz += az * share / 240
				bx += bvx / 240
				bz += bvz / 240
			end
			local beyond = length(bx, bz) - distance
			most = math.max(most, beyond)
			closest = math.min(closest, beyond)
			if beyond > BallConfig.ReboundSettleStuds then
				lastOut = frame / fps
			end
		end
		return most, lastOut, closest
	end

	test("#97: a 46 studs/s rebound stays inside the proposed limit, small and big, 60 and 30 fps", function()
		for _, fps in { 60, 30 } do
			for _, diameter in { 1.6, 4, 35 } do
				for _, share in { ROLLING, 1 } do
					local most, lastOut = rebound(diameter, 0, 46, share, fps, true)
					local label = `{fps} fps diameter {diameter} share {share}`
					T.isTrue(most <= BallConfig.ReboundMaxStuds, `{label}: {most} studs out`)
					T.isTrue(lastOut <= BallConfig.ReboundMaxSeconds, `{label}: back after {lastOut} s`)
				end
			end
		end
	end)

	test("#97 cause: without the rebound brake the same rebound rolls about 10 studs out", function()
		-- HoldMaxAcceleration alone (150, 107 as rolling speed) needs 46² / 214 ≈ 9.9 studs.
		local most = rebound(4, 0, 46, ROLLING, 60, false)
		T.isTrue(most > 3 * BallConfig.ReboundMaxStuds, `{most} studs out`)
	end)

	test("#97: a ball far out comes back without overshooting into the HumanoidRootPart", function()
		for _, fps in { 60, 30 } do
			for _, diameter in { 1.6, 4, 35 } do
				for _, offset in { 8, 20 } do
					local _, _, closest = rebound(diameter, offset, 0, ROLLING, fps, true)
					-- The ball's surface would reach the root part at -(HoldGap - ROOT_HALF_DEPTH).
					T.isTrue(
						closest > -(BallConfig.HoldGap - ROOT_HALF_DEPTH),
						`{fps} fps diameter {diameter} from {offset}: closest {closest}`
					)
				end
			end
		end
	end)

	test("#97: the rebound brake acts only on a ball beyond the hold distance that leaves", function()
		local distance = hold.holdDistance(4)
		local wantX, wantZ = hold.desiredVelocity(0, -distance - 1, 0, -1, distance, 0, 0, BallConfig.WalkSpeed)
		local _, _, leaving = hold.holdAcceleration(wantX, wantZ, 0, -40, 0, -distance - 1, 0, 0, distance)
		T.equal(leaving, true, "beyond and leaving")
		local _, _, returning = hold.holdAcceleration(wantX, wantZ, 0, 10, 0, -distance - 1, 0, 0, distance)
		T.equal(returning, false, "beyond and coming back")
		local insideX, insideZ = hold.desiredVelocity(0, -distance + 0.5, 0, -1, distance, 0, 0, BallConfig.WalkSpeed)
		local _, _, inside = hold.holdAcceleration(insideX, insideZ, 0, -40, 0, -distance + 0.5, 0, 0, distance)
		T.equal(inside, false, "inside the hold distance")
		-- Walking with the ball in front: the ball moves away from where the character was, but
		-- not away from the character, so it is no rebound.
		local walkX, walkZ = hold.desiredVelocity(0, -distance - 0.2, 0, -1, distance, 0, -16, BallConfig.WalkSpeed)
		local _, _, walking = hold.holdAcceleration(walkX, walkZ, 0, -15.5, 0, -distance - 0.2, 0, -16, distance)
		T.equal(walking, false, "pushing while walking")
		local ax, az, strong = hold.holdAcceleration(1e6, 0, 0, -1e3, 0, -distance - 5, 0, 0, distance)
		T.equal(strong, true)
		T.isTrue(length(ax, az) <= BallConfig.HoldReboundMaxAcceleration + BallConfig.HoldMaxAcceleration + 1e-6)
	end)

	test("#97: pushing straight on is unchanged, so the time to the maximum (#34 AC1) is too", function()
		for _, walkSpeed in { BallConfig.WalkSpeed, 32, 40 } do
			local sim = newSim(4)
			local distance = hold.holdDistance(4)
			for _ = 1, 60 do
				stepSim(sim, 4, 0, -1, walkSpeed)
			end
			for _ = 1, 2 * 60 do
				local rx, rz = sim.bx - sim.cx, sim.bz - sim.cz
				local cvz = -walkSpeed
				local wantX, wantZ = hold.desiredVelocity(rx, rz, 0, -1, distance, 0, cvz, walkSpeed)
				local ax, az, braking = hold.holdAcceleration(wantX, wantZ, sim.bvx, sim.bvz, rx, rz, 0, cvz, distance)
				local plainX, plainZ = hold.acceleration(wantX, wantZ, sim.bvx, sim.bvz)
				T.equal(braking, false, `walk speed {walkSpeed}: no rebound brake`)
				T.near(ax, plainX, 1e-9)
				T.near(az, plainZ, 1e-9)
				stepSim(sim, 4, 0, -1, walkSpeed)
			end
			T.near(length(sim.bvx, sim.bvz), walkSpeed, 0.1, `ball speed at walk speed {walkSpeed}`)
		end
	end)
end)

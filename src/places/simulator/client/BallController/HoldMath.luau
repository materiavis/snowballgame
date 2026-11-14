--!strict
-- Pure maths for holding the own ball in front of the character (concept 7.3, ADR 0002).
-- Works on plain x/z numbers and returns tuples, so the per-frame loop allocates nothing and
-- `lune run tests` (no Vector3) can check it. BallController binds it to Config.Ball.
--
-- The controller works in polar coordinates around the character: the distance is pulled to
-- the hold distance and the bearing swings towards the walking direction at a limited angular
-- speed. A ball that is behind therefore travels around the character, never through it.

export type HoldConfig = {
	HoldGap: number,
	HoldTurnRateDegrees: number,
	HoldMaxOrbitSpeedFactor: number,
	HoldCentripetalShare: number,
	HoldPositionGain: number,
	HoldVelocityGain: number,
	HoldMaxSpeedFactor: number,
	HoldMaxAcceleration: number,
	HoldApproachDeceleration: number,
	HoldContactMargin: number,
	HoldReboundGain: number,
	HoldReboundMaxAcceleration: number,
	MoveDeadzone: number,
	RecoveryHoldResetTime: number,
}

export type HoldMath = {
	holdDistance: (diameter: number) -> number,
	maxOrbitRate: (distance: number, walkSpeed: number) -> number,
	desiredVelocity: (
		rx: number,
		rz: number,
		hx: number,
		hz: number,
		distance: number,
		cvx: number,
		cvz: number,
		walkSpeed: number
	) -> (number, number),
	acceleration: (wantX: number, wantZ: number, bvx: number, bvz: number) -> (number, number),
	holdAcceleration: (
		wantX: number,
		wantZ: number,
		bvx: number,
		bvz: number,
		rx: number,
		rz: number,
		cvx: number,
		cvz: number,
		distance: number
	) -> (number, number, boolean),
	directionTo: (rx: number, rz: number, fallbackX: number, fallbackZ: number) -> (number, number),
	followsBall: (now: number, recoveredAt: number?) -> boolean,
	nextHeldDirection: (
		hx: number,
		hz: number,
		mx: number,
		mz: number,
		rx: number,
		rz: number,
		followBall: boolean,
		touchingObstacle: boolean?
	) -> (number, number),
	touchesBox: (
		x: number,
		y: number,
		z: number,
		halfX: number,
		halfY: number,
		halfZ: number,
		radius: number
	) -> boolean,
}

local EPSILON = 1e-6

-- Scales (x, z) down to at most `limit` length.
local function clampLength(x: number, z: number, limit: number): (number, number)
	local length = math.sqrt(x * x + z * z)
	if length > limit and length > 0 then
		local scale = limit / length
		return x * scale, z * scale
	end
	return x, z
end

local HoldMathModule = {}

function HoldMathModule.new(config: HoldConfig): HoldMath
	local turnRate = math.rad(config.HoldTurnRateDegrees)

	-- Same formula as BallCore.holdDistance on the server (a spec keeps them equal).
	local function holdDistance(diameter: number): number
		return diameter / 2 + config.HoldGap
	end

	-- Fastest swing around the character, rad/s. A big ball swings slower so its centre never
	-- moves sideways faster than the orbit limit, and staying on the circle never needs more
	-- than a share of the acceleration limit (otherwise the ball would cut the corner).
	local function maxOrbitRate(distance: number, walkSpeed: number): number
		local safeDistance = math.max(distance, EPSILON)
		local orbitRate = config.HoldMaxOrbitSpeedFactor * math.max(walkSpeed, 0) / safeDistance
		local curveRate = math.sqrt(config.HoldCentripetalShare * config.HoldMaxAcceleration / safeDistance)
		return math.min(turnRate, orbitRate, curveRate)
	end

	-- Velocity the ball should have. (rx, rz) is the ball relative to the character, (hx, hz)
	-- the unit hold direction, (cvx, cvz) the character's velocity (feed-forward, so the ball
	-- keeps pace without lagging into the character).
	local function desiredVelocity(
		rx: number,
		rz: number,
		hx: number,
		hz: number,
		distance: number,
		cvx: number,
		cvz: number,
		walkSpeed: number
	): (number, number)
		local current = math.sqrt(rx * rx + rz * rz)
		local bx, bz = hx, hz -- bearing; on top of the character, push out along the hold direction
		if current > EPSILON then
			bx, bz = rx / current, rz / current
		end
		local gain = config.HoldPositionGain
		-- Never faster towards the hold distance than the ball can still stop in (#97). With the
		-- plain gain a ball 8 studs out comes back at the speed cap, overshoots into the
		-- character and is pushed out again.
		local radialError = distance - current
		local stoppable = math.sqrt(2 * config.HoldApproachDeceleration * math.abs(radialError))
		local radialSpeed = math.clamp(radialError * gain, -stoppable, stoppable)
		-- Signed angle from the bearing to the hold direction. An exact reversal turns one
		-- fixed way, so it never stalls.
		local angle = math.atan2(bx * hz - bz * hx, bx * hx + bz * hz)
		local limit = maxOrbitRate(distance, walkSpeed)
		local angularSpeed = math.clamp(angle * gain, -limit, limit)
		local tangentialSpeed = angularSpeed * math.max(current, distance)
		-- Tangent = bearing turned +90° (same sign convention as the angle).
		local wantX = cvx + bx * radialSpeed - bz * tangentialSpeed
		local wantZ = cvz + bz * radialSpeed + bx * tangentialSpeed
		return clampLength(wantX, wantZ, config.HoldMaxSpeedFactor * math.max(walkSpeed, 0))
	end

	-- Acceleration towards the desired velocity, limited so a far-off ball is not flung.
	local function acceleration(wantX: number, wantZ: number, bvx: number, bvz: number): (number, number)
		local gain = config.HoldVelocityGain
		return clampLength((wantX - bvx) * gain, (wantZ - bvz) * gain, config.HoldMaxAcceleration)
	end

	-- Acceleration while a character holds the ball. (rx, rz) is the ball relative to the
	-- character, (cvx, cvz) the character's velocity. As `acceleration`, except for a ball beyond
	-- the hold distance that moves away from the character (a rebound, #97): the part towards
	-- the character may then brake that outward speed at HoldReboundGain, up to
	-- HoldReboundMaxAcceleration. Only the outward speed itself: everything else, including
	-- pressing a ball against an obstacle, keeps HoldMaxAcceleration (#97 round 1: in round 0
	-- solver jitter of a pressed ball unlocked the whole unclamped command, up to 800). The
	-- third value is true while this brake is stronger than the normal one.
	local function holdAcceleration(
		wantX: number,
		wantZ: number,
		bvx: number,
		bvz: number,
		rx: number,
		rz: number,
		cvx: number,
		cvz: number,
		distance: number
	): (number, number, boolean)
		local x, z = acceleration(wantX, wantZ, bvx, bvz)
		local current = math.sqrt(rx * rx + rz * rz)
		if current > distance and current > EPSILON then
			local bx, bz = rx / current, rz / current
			local outward = (bvx - cvx) * bx + (bvz - cvz) * bz
			local brake = math.max(-outward * config.HoldReboundGain, -config.HoldReboundMaxAcceleration)
			local radial = x * bx + z * bz
			if brake < radial and brake < -config.HoldMaxAcceleration then
				return x + (brake - radial) * bx, z + (brake - radial) * bz, true
			end
		end
		return x, z, false
	end

	-- Unit direction of (rx, rz), or the fallback when it is too short to have one.
	local function directionTo(rx: number, rz: number, fallbackX: number, fallbackZ: number): (number, number)
		local length = math.sqrt(rx * rx + rz * rz)
		if length > 1e-3 and length == length then
			return rx / length, rz / length
		end
		return fallbackX, fallbackZ
	end

	-- True for RecoveryHoldResetTime seconds after the client saw a server recovery. A window,
	-- not one frame: the new position and the Recoveries attribute need not arrive in the same
	-- frame, and the hold must end up aimed at where the ball was put, not where it fell.
	local function followsBall(now: number, recoveredAt: number?): boolean
		return recoveredAt ~= nil and now - recoveredAt < config.RecoveryHoldResetTime
	end

	-- The hold direction for this frame; (rx, rz) is the ball relative to the character.
	-- Walking always wins: walking is the steering (7.3), so a player who walks out over the
	-- edge again pushes the ball over again. Standing still right after a recovery, the hold
	-- follows the ball to where the server put it, so the old direction (over the edge, into an
	-- obstacle) does not swing it back (#94). Otherwise the last walking direction stays.
	-- While the own ball touches an obstacle (#97 rounds 2 and 3), walking or standing, the hold
	-- keeps the ball's current bearing instead: its hold point would lie inside the obstacle, and
	-- swinging towards it drives the ball along the face and round the corner, or keeps a ball
	-- resting beside a face pressed into it. Once free, walking steers again.
	local function nextHeldDirection(
		hx: number,
		hz: number,
		mx: number,
		mz: number,
		rx: number,
		rz: number,
		followBall: boolean,
		touchingObstacle: boolean?
	): (number, number)
		local moving = math.sqrt(mx * mx + mz * mz)
		if touchingObstacle then
			if moving > config.MoveDeadzone then
				return directionTo(rx, rz, mx / moving, mz / moving)
			end
			return directionTo(rx, rz, hx, hz)
		end
		if moving > config.MoveDeadzone then
			return mx / moving, mz / moving
		end
		if followBall then
			return directionTo(rx, rz, hx, hz)
		end
		return hx, hz
	end

	-- Whether a ball of `radius` with its centre at (x, y, z) in a box's own space touches the box
	-- of half size (halfX, halfY, halfZ), within HoldContactMargin. Same box distance as the
	-- server's ObstacleRules; this one only steers the own ball's hold, it decides no collision.
	local function touchesBox(
		x: number,
		y: number,
		z: number,
		halfX: number,
		halfY: number,
		halfZ: number,
		radius: number
	): boolean
		local dx = math.max(math.abs(x) - halfX, 0)
		local dy = math.max(math.abs(y) - halfY, 0)
		local dz = math.max(math.abs(z) - halfZ, 0)
		local reach = radius + config.HoldContactMargin
		return dx * dx + dy * dy + dz * dz <= reach * reach
	end

	return table.freeze({
		touchesBox = touchesBox,
		holdDistance = holdDistance,
		maxOrbitRate = maxOrbitRate,
		desiredVelocity = desiredVelocity,
		acceleration = acceleration,
		holdAcceleration = holdAcceleration,
		directionTo = directionTo,
		followsBall = followsBall,
		nextHeldDirection = nextHeldDirection,
	})
end

return table.freeze(HoldMathModule)

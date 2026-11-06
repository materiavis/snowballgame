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
		local radialSpeed = (distance - current) * gain
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

	return table.freeze({
		holdDistance = holdDistance,
		maxOrbitRate = maxOrbitRate,
		desiredVelocity = desiredVelocity,
		acceleration = acceleration,
	})
end

return table.freeze(HoldMathModule)

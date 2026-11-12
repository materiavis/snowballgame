--!strict
-- Pure recovery rules for BallService (concept 7.3, ADR 0002 "Recovery", issue #94): where to
-- look for a safe put-back position, what makes one safe, how many recoveries may follow each
-- other (burst and same-place loop), and when a ball out of the character's range counts as
-- stuck. No Instances, so `lune run tests` loads it; SafeSpot and BallStep do the Roblox side.

export type RecoveryConfig = {
	RecoveryBearingStepDegrees: number,
	RecoveryRingSteps: { number },
	RecoverySupportShare: number,
	RecoverySupportSlope: number,
	RecoveryObstacleClearance: number,
	RecoveryPenetrationTolerance: number,
	RecoveryGraceTime: number,
	RecoveryBurstLimit: number,
	RecoveryBurstWindow: number,
	RecoveryLoopLimit: number,
	RecoveryLoopWindow: number,
	RecoveryLoopRadiusMin: number,
	RecoveryLoopRadiusPerDiameter: number,
	StuckTime: number,
	StuckProgressStuds: number,
	StuckSlopeDegrees: number,
	GrowthRange: number,
	GrowthVerticalRange: number,
}

-- Offset of a candidate centre from the character on the ground plane. `bearing` is degrees
-- from the facing direction (0 = straight in front), `ring` the studs beyond the hold distance.
export type Candidate = { x: number, z: number, bearing: number, ring: number }

export type Offset = { x: number, z: number }

-- Out-of-range timer of one ball. The anchor is where the ball was, and how far from the
-- character, when the current timing started.
export type StuckTracker = {
	time: number,
	anchorX: number,
	anchorZ: number,
	anchorDistance: number,
}

-- One earlier recovery for the loop bound: when, and where the ball was put back.
export type PutBack = { time: number, x: number, z: number }

export type StuckFacts = {
	inRange: boolean,
	distance: number,
	x: number,
	z: number,
	elapsed: number,
}

export type RecoveryRules = {
	candidates: (lookX: number, lookZ: number, holdDistance: number) -> { Candidate },
	supportOffsets: (radius: number) -> { Offset },
	isSupported: (centreGround: number?, supportGrounds: { [number]: number? }, radius: number) -> boolean,
	blocksPlacement: (distance: number, radius: number, isObstacle: boolean) -> boolean,
	recentRecoveries: (times: { number }, now: number) -> { number },
	atBound: (recentCount: number) -> boolean,
	loopRadius: (diameter: number) -> number,
	recentPutBacks: (history: { PutBack }, now: number) -> { PutBack },
	nearPutBacks: (history: { PutBack }, x: number, z: number, diameter: number) -> number,
	atLoopBound: (nearCount: number) -> boolean,
	inGrace: (now: number, placedAt: number) -> boolean,
	stuckStep: (tracker: StuckTracker?, facts: StuckFacts) -> (StuckTracker?, boolean),
	restingHeight: (groundY: number, normalY: number, radius: number) -> number?,
	heldOnSlope: (horizontal: number, ballGroundY: number?, characterGroundY: number?, diameter: number) -> boolean,
}

local SUPPORT_POINTS = 4 -- supportOffsets returns this many
local MIN_NORMAL_Y = 0.1 -- steeper than about 84°: a wall, not ground to rest on

local RecoveryRulesModule = {}

function RecoveryRulesModule.new(config: RecoveryConfig): RecoveryRules
	local step = config.RecoveryBearingStepDegrees
	assert(step > 0 and step <= 180, "Config.Ball.RecoveryBearingStepDegrees must be in (0, 180]")
	assert(#config.RecoveryRingSteps >= 1, "Config.Ball.RecoveryRingSteps needs at least one ring")
	assert(config.RecoveryBurstLimit >= 1, "Config.Ball.RecoveryBurstLimit must be at least 1")
	assert(config.RecoveryLoopLimit >= 1, "Config.Ball.RecoveryLoopLimit must be at least 1")
	assert(
		config.StuckSlopeDegrees >= 0 and config.StuckSlopeDegrees < 90,
		"Config.Ball.StuckSlopeDegrees must be in [0, 90)"
	)
	local slopeTan = math.tan(math.rad(config.StuckSlopeDegrees))
	assert(
		config.RecoveryLoopWindow >= config.RecoveryBurstWindow,
		"Config.Ball.RecoveryLoopWindow must be at least RecoveryBurstWindow"
	)

	-- 0, +step, -step, +2 step, -2 step, … up to 180 (once). Front first, then the nearest
	-- bearings to it, so the ball lands as close to "in front" as the ground allows.
	local bearings: { number } = { 0 }
	local i = 1
	while i * step < 180 - 1e-9 do
		table.insert(bearings, i * step)
		table.insert(bearings, -i * step)
		i += 1
	end
	if math.abs(i * step - 180) < 1e-9 then
		table.insert(bearings, 180)
	end
	table.freeze(bearings)

	-- Ordered by bearing, then ring: a slightly farther spot in front beats one to the side.
	local function candidates(lookX: number, lookZ: number, holdDistance: number): { Candidate }
		local length = math.sqrt(lookX * lookX + lookZ * lookZ)
		if length < 1e-3 or length ~= length then
			lookX, lookZ, length = 0, -1, 1
		end
		lookX, lookZ = lookX / length, lookZ / length
		local result: { Candidate } = {}
		for _, bearing in bearings do
			local angle = math.rad(bearing)
			local cos, sin = math.cos(angle), math.sin(angle)
			local dirX = lookX * cos - lookZ * sin
			local dirZ = lookX * sin + lookZ * cos
			for _, ring in config.RecoveryRingSteps do
				local distance = holdDistance + ring
				table.insert(result, { x = dirX * distance, z = dirZ * distance, bearing = bearing, ring = ring })
			end
		end
		return result
	end

	-- Points around the centre that must have ground too, so the ball does not sit balanced on
	-- the edge of a cliff or a hole and roll off at the first push.
	local function supportOffsets(radius: number): { Offset }
		local d = radius * config.RecoverySupportShare
		return { { x = d, z = 0 }, { x = -d, z = 0 }, { x = 0, z = d }, { x = 0, z = -d } }
	end

	-- `centreGround` and `supportGrounds[i]` are ground heights found below the centre and the
	-- i-th support point (nil = no ground). Indexed, not iterated: a nil would end an array
	-- loop early and a missing point would pass unseen. A support point may differ from the
	-- centre by RecoverySupportSlope × its offset (1 = a 45° slope).
	local function isSupported(centreGround: number?, supportGrounds: { [number]: number? }, radius: number): boolean
		if centreGround == nil then
			return false
		end
		local allowed = radius * config.RecoverySupportShare * config.RecoverySupportSlope
		for index = 1, SUPPORT_POINTS do
			local ground = supportGrounds[index]
			if ground == nil or math.abs(ground - centreGround) > allowed then
				return false
			end
		end
		return true
	end

	-- `distance` is from the ball centre to a part's box. Obstacles keep a clearance beyond the
	-- contact margin, so the first sample sees no contact; other parts (the ground it rests on,
	-- a neighbouring tile) may touch but not reach into the ball.
	local function blocksPlacement(distance: number, radius: number, isObstacle: boolean): boolean
		if isObstacle then
			return distance < radius + config.RecoveryObstacleClearance
		end
		return distance < radius - config.RecoveryPenetrationTolerance
	end

	-- The recovery times still inside RecoveryBurstWindow, oldest first.
	local function recentRecoveries(times: { number }, now: number): { number }
		local kept: { number } = {}
		for _, time in times do
			if now - time < config.RecoveryBurstWindow then
				table.insert(kept, time)
			end
		end
		return kept
	end

	-- `recentCount` recoveries already happened in the window; one more is past the bound.
	local function atBound(recentCount: number): boolean
		return recentCount >= config.RecoveryBurstLimit
	end

	-- Put-backs this close count as the same place. Grows with the ball: a big ball's safe spot
	-- shifts by more when the character turns a little.
	local function loopRadius(diameter: number): number
		return math.max(config.RecoveryLoopRadiusMin, diameter * config.RecoveryLoopRadiusPerDiameter)
	end

	-- The put-backs still inside RecoveryLoopWindow, oldest first.
	local function recentPutBacks(history: { PutBack }, now: number): { PutBack }
		local kept: { PutBack } = {}
		for _, entry in history do
			if now - entry.time < config.RecoveryLoopWindow then
				table.insert(kept, entry)
			end
		end
		return kept
	end

	-- How many of `history` lie near (x, z) on the ground plane.
	local function nearPutBacks(history: { PutBack }, x: number, z: number, diameter: number): number
		local radius = loopRadius(diameter)
		local count = 0
		for _, entry in history do
			local dx, dz = entry.x - x, entry.z - z
			if dx * dx + dz * dz <= radius * radius then
				count += 1
			end
		end
		return count
	end

	-- `nearCount` earlier put-backs at the same place in the window; this one is past the bound.
	local function atLoopBound(nearCount: number): boolean
		return nearCount >= config.RecoveryLoopLimit
	end

	local function inGrace(now: number, placedAt: number): boolean
		return now - placedAt < config.RecoveryGraceTime
	end

	-- Out of growth range for StuckTime while the ball neither moved StuckProgressStuds on the
	-- ground plane nor came that much closer: held behind something. A ball that chases the
	-- character, swings round it or coasts keeps moving, so the timer starts over.
	local function stuckStep(tracker: StuckTracker?, facts: StuckFacts): (StuckTracker?, boolean)
		if facts.inRange then
			return nil, false
		end
		local function restart(): StuckTracker
			return { time = 0, anchorX = facts.x, anchorZ = facts.z, anchorDistance = facts.distance }
		end
		if tracker == nil then
			return restart(), false
		end
		local dx, dz = facts.x - tracker.anchorX, facts.z - tracker.anchorZ
		local moved = math.sqrt(dx * dx + dz * dz)
		local closer = tracker.anchorDistance - facts.distance
		if moved >= config.StuckProgressStuds or closer >= config.StuckProgressStuds then
			return restart(), false
		end
		local elapsed = if facts.elapsed > 0 and facts.elapsed == facts.elapsed then facts.elapsed else 0
		local advanced = {
			time = tracker.time + elapsed,
			anchorX = tracker.anchorX,
			anchorZ = tracker.anchorZ,
			anchorDistance = tracker.anchorDistance,
		}
		return advanced, advanced.time >= config.StuckTime
	end

	-- Centre height of a ball resting on a plane through (·, groundY, ·) with the unit normal's
	-- Y `normalY`, straight above the ray hit. On a slope the centre sits radius / cos(slope)
	-- above the hit, not radius: placed at radius it would reach into the slope (#94 ramp). nil
	-- for a wall or an overhang.
	local function restingHeight(groundY: number, normalY: number, radius: number): number?
		if not (normalY > MIN_NORMAL_Y) or normalY ~= normalY then
			return nil
		end
		return groundY + radius / math.min(normalY, 1)
	end

	-- Reach for the stuck rule only (#94 round 2, owner rule): a ball held normally in front of
	-- a character on a slope is not stuck, although the height difference puts it outside the
	-- growth range. It counts as held when it is within the growth range on the ground plane
	-- and the ground under it is at most GrowthVerticalRange plus a StuckSlopeDegrees slope
	-- over that distance above or below the character's ground. A cliff is steeper, so a ball at
	-- its foot still counts as stuck. nil grounds (in the air) do not count as held.
	local function heldOnSlope(
		horizontal: number,
		ballGroundY: number?,
		characterGroundY: number?,
		diameter: number
	): boolean
		if ballGroundY == nil or characterGroundY == nil or horizontal ~= horizontal then
			return false
		end
		if horizontal - diameter / 2 > config.GrowthRange then
			return false
		end
		local allowed = config.GrowthVerticalRange + math.max(horizontal, 0) * slopeTan
		return math.abs(ballGroundY - characterGroundY) <= allowed
	end

	return table.freeze({
		candidates = candidates,
		supportOffsets = supportOffsets,
		isSupported = isSupported,
		blocksPlacement = blocksPlacement,
		recentRecoveries = recentRecoveries,
		atBound = atBound,
		loopRadius = loopRadius,
		recentPutBacks = recentPutBacks,
		nearPutBacks = nearPutBacks,
		atLoopBound = atLoopBound,
		inGrace = inGrace,
		stuckStep = stuckStep,
		restingHeight = restingHeight,
		heldOnSlope = heldOnSlope,
	})
end

return table.freeze(RecoveryRulesModule)

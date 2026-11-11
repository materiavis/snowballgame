--!strict
-- One server sample of one ball for BallService (concept 7.3, 7.4, ADR 0002): recovery checks,
-- surface, track, obstacles and growth. Roblox-facing glue; the rules are in the pure
-- BallCore, GrowthRules, ObstacleRules, RecoveryRules and SurfaceService/TrackGrid modules.

export type BallState = {
	player: Player,
	part: Part,
	root: BasePart?,
	humanoid: Humanoid?,
	zone: number,
	fraction: number,
	lastPosition: Vector3,
	lastSampleTime: number,
	wasGrounded: boolean,
	outOfReachFor: number,
	recoveries: number,
	-- Recovery (#94): when the ball was last placed, recent recovery times for the bound, the
	-- park end while the bound holds the ball, the stuck timer and the last spot it stayed at.
	placedAt: number,
	recentRecoveries: { number },
	parkedUntil: number?,
	stuck: any,
	lastSafePosition: Vector3?,
	lastRecovery: string,
	recoverySpot: string,
	credit: number,
	track: any,
	contacts: { [any]: boolean }?,
	protectedUntil: number,
	lastCollisionLoss: number,
	collisions: number,
	knockOvers: number,
	surface: string,
	growthBlock: string?,
	isMax: boolean,
	rolledStuds: number,
	countedStuds: number,
	growthSeconds: number,
	growthStartedAt: number?,
	measuredTimeToMax: number?,
	lastPublish: number,
	sentPart: { [string]: any },
	sentPlayer: { [string]: any },
}

export type Deps = {
	config: any,
	core: any,
	rules: any,
	obstacleRules: any,
	recoveryRules: any,
	obstacles: any,
	modifiers: any,
	surfaces: any,
	attributes: any,
	groundParams: RaycastParams,
	isPaused: () -> boolean,
	recover: (state: BallState, root: BasePart, why: string) -> (),
	-- Ends a park whose time is over; returns whether the ball is still parked.
	updatePark: (state: BallState, now: number) -> boolean,
	applyOptics: (state: BallState, force: boolean) -> (),
}

export type BallStep = {
	update: (state: BallState, now: number) -> (),
	applyCollision: (state: BallState, now: number) -> boolean,
}

local AIR = "Air"
local PARKED = "Parked" -- GrowthBlock while the recovery bound holds the ball (#94)

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local BallStepModule = {}

-- State of a new ball at start size. BallService creates the part afterwards.
function BallStepModule.newState(
	player: Player,
	root: BasePart,
	humanoid: Humanoid?,
	zone: number,
	track: any
): BallState
	return {
		player = player,
		part = nil :: any,
		root = root,
		humanoid = humanoid,
		zone = zone,
		fraction = 0,
		lastPosition = Vector3.zero,
		lastSampleTime = os.clock(),
		wasGrounded = false,
		outOfReachFor = 0,
		recoveries = 0,
		placedAt = 0,
		recentRecoveries = {},
		parkedUntil = nil,
		stuck = nil,
		lastSafePosition = nil,
		lastRecovery = "",
		recoverySpot = "",
		credit = 0,
		track = track,
		contacts = nil,
		protectedUntil = 0,
		lastCollisionLoss = 0,
		collisions = 0,
		knockOvers = 0,
		surface = "",
		growthBlock = nil,
		isMax = false,
		rolledStuds = 0,
		countedStuds = 0,
		growthSeconds = 0,
		growthStartedAt = nil,
		measuredTimeToMax = nil,
		lastPublish = 0,
		sentPart = {},
		sentPlayer = {},
	}
end

function BallStepModule.new(deps: Deps): BallStep
	local config = deps.config
	local core = deps.core
	local rules = deps.rules

	local function groundHit(part: BasePart): RaycastResult?
		local radius = part.Size.X / 2
		local length = radius + config.GroundCheckMargin + radius * config.GroundCheckMarginPerRadius
		return workspace:Raycast(part.Position, Vector3.new(0, -length, 0), deps.groundParams)
	end

	-- A collision costs size unless the protection of the last one is still running. Returns
	-- whether it cost anything.
	local function applyCollision(state: BallState, now: number): boolean
		if now < state.protectedUntil then
			state.lastCollisionLoss = 0
			return false
		end
		local fraction, lost = rules.collide(state.zone, state.fraction, deps.modifiers.collisionLoss(state.player))
		state.fraction = fraction
		state.lastCollisionLoss = lost
		state.protectedUntil = now + config.CollisionProtection
		state.collisions += 1
		return true
	end

	local function handleObstacles(state: BallState, position: Vector3, diameter: number, now: number)
		local outcome = deps.obstacleRules.evaluate(
			state.contacts,
			deps.obstacles.contactsAt(position, diameter / 2),
			now < state.protectedUntil,
			function(obstacleSize: any): boolean
				return rules.canKnockOver(diameter, obstacleSize)
			end
		)
		state.contacts = outcome.contacts
		for _, obstacle in outcome.knockOvers do
			deps.obstacles.knockOver(obstacle)
			state.knockOvers += 1
		end
		if outcome.hit then
			applyCollision(state, now)
		end
	end

	-- The character the growth check looks at: alive and in the world, or nil.
	local function livingRoot(state: BallState): BasePart?
		local root, humanoid = state.root, state.humanoid
		if root and root.Parent and humanoid and humanoid.Health > 0 then
			return root
		end
		return nil
	end

	local function growBall(state: BallState, surface: string, grounded: boolean, facts: any, now: number)
		local position: Vector3 = facts.position
		local distance: number = facts.distance
		local elapsed: number = facts.elapsed
		local diameter = state.part.Size.X
		local multiplier = rules.surfaceMultiplier(surface)
		local onTrack = state.track.advance(position.X, position.Z, now, distance, multiplier > 0)

		local root = livingRoot(state)
		local offset = if root then root.Position - position else Vector3.zero
		local block = rules.growthBlock({
			paused = deps.isPaused(),
			atMax = state.fraction >= 1,
			hasCharacter = root ~= nil,
			inRange = rules.inGrowthRange(flat(offset).Magnitude, offset.Y, diameter),
			grounded = grounded and state.wasGrounded,
			surface = surface,
			onTrack = onTrack,
			distance = distance,
		})
		state.growthBlock = block

		-- A blocked sample still refills the credit, so the limit is a limit over time.
		local counted, credit = rules.consumeCredit(state.credit, if block == nil then distance else 0, elapsed)
		state.credit = credit
		if block ~= nil then
			return
		end
		local perStud = rules.fractionPerStud(deps.modifiers.timeToMax(state.player))
		state.fraction = rules.grow(state.fraction, counted, perStud, multiplier)
		state.countedStuds += counted
		state.growthSeconds += elapsed
		if state.growthStartedAt == nil then
			state.growthStartedAt = now
		end
		if state.fraction >= 1 and state.measuredTimeToMax == nil then
			state.measuredTimeToMax = now - (state.growthStartedAt :: number)
		end
	end

	-- Whether a living character is in growth range of the ball at `position`.
	local function characterInRange(state: BallState, position: Vector3): boolean
		local root = livingRoot(state)
		if root == nil then
			return false
		end
		local offset = root.Position - position
		return rules.inGrowthRange(flat(offset).Magnitude, offset.Y, state.part.Size.X)
	end

	-- Leash (far away for LeashTime), then stuck (#94 AC8: out of growth range without
	-- progress for StuckTime). Returns whether the ball was put back.
	local function checkReach(state: BallState, root: BasePart, position: Vector3, elapsed: number): boolean
		local horizontal = flat(position - root.Position).Magnitude
		if core.isOutOfReach(horizontal, state.part.Size.X) then
			state.outOfReachFor += elapsed
			if core.leashExpired(state.outOfReachFor) then
				deps.recover(state, root, "out of reach")
				return true
			end
		else
			state.outOfReachFor = 0
		end
		if livingRoot(state) == nil then
			state.stuck = nil
			return false
		end
		local tracker, stuck = deps.recoveryRules.stuckStep(state.stuck, {
			inRange = characterInRange(state, position),
			distance = horizontal,
			x = position.X,
			z = position.Z,
			elapsed = elapsed,
		})
		state.stuck = tracker
		if stuck then
			deps.recover(state, root, "stuck")
			return true
		end
		return false
	end

	local function update(state: BallState, now: number)
		if deps.updatePark(state, now) then
			state.growthBlock = PARKED
			deps.attributes.publish(state, now, false)
			return
		end
		local part = state.part
		local root = state.root
		local rootAlive = root ~= nil and root.Parent ~= nil
		if not part.Parent or part.Position.Y < config.ResetBelowY then
			-- Right after a placement the owner's packets can still carry the old position, which
			-- must not count as a new fall (#94).
			if part.Parent and deps.recoveryRules.inGrace(now, state.placedAt) then
				return
			end
			if root and rootAlive then
				deps.recover(state, root, if part.Parent then "fell" else "missing")
			end
			return
		end

		local position = part.Position
		local elapsed = now - state.lastSampleTime

		if root and rootAlive and checkReach(state, root, position, elapsed) then
			return
		end

		local hit = groundHit(part)
		local grounded = hit ~= nil
		local surface = if hit then deps.surfaces.classify(hit.Instance) else AIR
		-- Horizontal only: a resize moves the centre vertically, and that is not rolling.
		local distance = flat(position - state.lastPosition).Magnitude
		state.surface = surface
		state.rolledStuds += distance

		handleObstacles(state, position, part.Size.X, now)
		growBall(state, surface, grounded, {
			position = position,
			distance = distance,
			elapsed = elapsed,
		}, now)

		-- The last place the ball stayed on the ground, clear of obstacles, with the character at
		-- it: the put-back spot when none is found around the character. SafeSpot checks it again.
		local contacts = state.contacts
		if grounded and state.wasGrounded and (contacts == nil or next(contacts) == nil) then
			if characterInRange(state, position) then
				state.lastSafePosition = position
			end
		end

		state.lastPosition = position
		state.lastSampleTime = now
		state.wasGrounded = grounded

		if grounded then
			deps.applyOptics(state, false)
		end
		deps.attributes.publish(state, now, false)
	end

	return table.freeze({
		update = update,
		applyCollision = applyCollision,
	})
end

return table.freeze(BallStepModule)

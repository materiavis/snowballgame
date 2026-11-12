--!strict
-- Places and puts back the ball for BallService (concept 7.3, ADR 0002 "Recovery", issue #94):
-- first spawn, character respawn, fell, missing, out of reach, stuck and the Studio switches.
-- Roblox-facing; where the ball goes is SafeSpot, the bound and the timers are RecoveryRules.
--
-- The server alone decides the position, from the character's replicated root part and the
-- world. No client value is read.

export type Recovery = {
	-- Puts the ball at a safe spot without counting a recovery (spawn, respawn).
	place: (state: any, root: BasePart) -> (),
	recover: (state: any, root: BasePart, why: string) -> (),
	-- Puts the ball at an exact position without counting a recovery (Studio switch).
	moveTo: (state: any, position: Vector3) -> (),
	-- Ends a park whose time is over; returns whether the ball is still parked.
	updatePark: (state: any, now: number) -> boolean,
}

export type Deps = {
	config: any,
	recoveryRules: any,
	safeSpot: any,
	visualDiameter: (zone: number, fraction: number) -> number,
	createPart: (state: any, diameter: number, position: Vector3) -> Part,
	publish: (state: any) -> (),
	assignOwner: (state: any) -> (),
	verbose: boolean,
}

local function show(position: Vector3?): string
	if position == nil then
		return "none"
	end
	return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

local RecoveryModule = {}

function RecoveryModule.new(deps: Deps): Recovery
	local config = deps.config
	local recoveryRules = deps.recoveryRules

	-- Moves (or creates) the ball at `position` and starts the sample state over. Ownership
	-- goes back to the player at the end.
	local function settle(state: any, position: Vector3, diameter: number)
		local part: Part? = state.part
		if part and part.Parent then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			part.Size = Vector3.one * diameter
			part.CFrame = CFrame.new(position)
		else
			state.part = deps.createPart(state, diameter, position)
		end
		local now = os.clock()
		deps.publish(state)
		state.lastPosition = position
		state.lastSampleTime = now
		state.placedAt = now
		state.wasGrounded = false
		state.outOfReachFor = 0
		state.stuck = nil
		-- Whatever the ball was placed on was not rolled into (ObstacleRules.evaluate). The first
		-- sample may not see the contact yet, so protection covers the samples right after it: a
		-- contact first seen while protected is remembered without a loss.
		state.contacts = nil
		state.protectedUntil = math.max(state.protectedUntil, now + config.CollisionProtection)
		deps.assignOwner(state)
	end

	-- Returns the chosen spot.
	local function put(state: any, root: BasePart): any
		local diameter = deps.visualDiameter(state.zone, state.fraction)
		local spot = deps.safeSpot.find(root, diameter, state.lastSafePosition)
		state.recoverySpot = spot.kind
		settle(state, spot.position, diameter)
		return spot
	end

	-- The replicated count the client hold follows (with Recoveries), for server moves that are
	-- not recoveries.
	local function countPlacement(state: any)
		state.placements += 1
		state.part:SetAttribute(config.PlacementsAttribute, state.placements)
	end

	-- Puts the ball exactly at `position` (Studio switch BallPlaceBehindObstacle). Not a
	-- recovery: no Recoveries, no bound, no recovery line.
	local function moveTo(state: any, position: Vector3)
		settle(state, position, state.part.Size.X)
		countPlacement(state)
	end

	local function park(state: any, now: number)
		state.parkedUntil = now + config.RecoveryParkTime
		state.part.Anchored = true
	end

	local function updatePark(state: any, now: number): boolean
		local parkedUntil = state.parkedUntil
		if parkedUntil == nil then
			return false
		end
		if now < parkedUntil then
			return true
		end
		state.parkedUntil = nil
		local part: Part = state.part
		if part.Parent then
			part.Anchored = false
			state.lastPosition = part.Position
			state.lastSampleTime = now
			state.placedAt = now
			state.wasGrounded = false
			state.outOfReachFor = 0
			state.stuck = nil
			deps.assignOwner(state)
		end
		if deps.verbose then
			print(`[BallService] {state.player.Name} ball released after the recovery bound at {show(part.Position)}`)
		end
		return false
	end

	local function place(state: any, root: BasePart)
		local spot = put(state, root)
		countPlacement(state)
		if spot.kind == "Unsafe" then
			warn(
				`[BallService] {state.player.Name} no safe spot for the ball at character {show(root.Position)}, placed in front at {show(
					spot.position
				)}`
			)
		end
	end

	local function recover(state: any, root: BasePart, why: string)
		local now = os.clock()
		local part: Part? = state.part
		local ballBefore = if part and part.Parent then part.Position else nil
		local recent = recoveryRules.recentRecoveries(state.recentRecoveries, now)
		local bounded = recoveryRules.atBound(#recent)
		table.insert(recent, now)
		state.recentRecoveries = recent
		state.recoveries += 1
		state.lastRecovery = why

		local spot = put(state, root)
		local putBack: Vector3 = spot.position
		-- Loop bound: needs the put-back position, so it is decided after the placement.
		local size = state.part.Size.X
		local putBacks = recoveryRules.recentPutBacks(state.recentPutBacks, now)
		local near = recoveryRules.nearPutBacks(putBacks, putBack.X, putBack.Z, size)
		local looped = recoveryRules.atLoopBound(near)
		table.insert(putBacks, { time = now, x = putBack.X, z = putBack.Z })
		state.recentPutBacks = putBacks

		state.part:SetAttribute(config.RecoveriesAttribute, state.recoveries)
		local name = state.player.Name
		local diameter = string.format("%.2f", size)
		if deps.verbose then
			print(
				`[BallService] {name} recovery reason={why} ball={show(ballBefore)} character={show(root.Position)} putBack={show(
					putBack
				)} spot={spot.kind} diameter={diameter} recoveries={state.recoveries} recent={#recent} loop={near + 1}`
			)
		end
		if spot.kind == "Unsafe" then
			warn(`[BallService] {name} no safe spot for the ball ({why}), put back in front at {show(putBack)}`)
		end
		if bounded then
			park(state, now)
			warn(
				`[BallService] {name} recovery bound: {#recent} recoveries within {config.RecoveryBurstWindow} s, ball parked at {show(
					putBack
				)} ({spot.kind}) for {config.RecoveryParkTime} s`
			)
		elseif looped then
			park(state, now)
			warn(
				`[BallService] {name} recovery loop bound: {near + 1} recoveries within {config.RecoveryLoopWindow} s and {string.format(
					"%.1f",
					recoveryRules.loopRadius(size)
				)} studs, ball parked at {show(putBack)} ({spot.kind}) for {config.RecoveryParkTime} s`
			)
		end
	end

	return table.freeze({
		place = place,
		moveTo = moveTo,
		recover = recover,
		updatePark = updatePark,
	})
end

return table.freeze(RecoveryModule)

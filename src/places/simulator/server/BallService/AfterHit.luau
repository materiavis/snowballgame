--!strict
-- What follows an obstacle touch, for BallStep (issue #97, ADR 0002 "After a hit"):
-- the same-hit memory (D2) and the Studio-only rebound watch and log (D1). Roblox-facing glue;
-- the rules are in the pure HitRules.
--
-- Only server views are used: the replicated ball position and the character's replicated
-- root part. Nothing from the client decides anything here.

export type Deps = {
	config: any,
	hitRules: any,
	holdDistance: (diameter: number) -> number,
	-- Gap between the ball's surface and an obstacle, nil once it is out of the world.
	gapTo: (obstacle: any, position: Vector3, radius: number) -> number?,
	verbose: boolean, -- Studio at PlaceId 0: log lines
	isTracing: () -> boolean, -- Studio switch BallHitTrace: one line per sample while watched
}

export type AfterHit = {
	-- Before ObstacleRules.evaluate: forgets obstacles the ball has clearly left and returns
	-- the same-hit check to pass to it.
	sameHitCheck: (state: any, position: Vector3, radius: number) -> (obstacle: any) -> boolean,
	-- After it: remembers this sample's contacts, counts repeats, starts the rebound watch.
	noteOutcome: (state: any, outcome: any, counted: boolean, position: Vector3, root: BasePart?, now: number) -> (),
	-- Every sample: steps and ends the rebound watch.
	step: (state: any, position: Vector3, root: BasePart?, now: number, elapsed: number) -> (),
}

local function show(position: Vector3?): string
	if position == nil then
		return "none"
	end
	return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

-- Two decimals for the log, or "none".
local function number(value: number?): string
	return if value then string.format("%.2f", value) else "none"
end

local function round(value: number, decimals: number): number
	local scale = 10 ^ decimals
	return math.round(value * scale) / scale
end

local function nameOf(obstacle: any): string
	return if typeof(obstacle) == "Instance" then obstacle.Name else tostring(obstacle)
end

local AfterHitModule = {}

function AfterHitModule.new(deps: Deps): AfterHit
	local config = deps.config
	local hitRules = deps.hitRules

	-- Centre distance beyond the hold distance on the ground plane; nil without a character.
	local function beyondHold(position: Vector3, root: BasePart?, diameter: number): number?
		if root == nil then
			return nil
		end
		local offset = position - root.Position
		return Vector3.new(offset.X, 0, offset.Z).Magnitude - deps.holdDistance(diameter)
	end

	local function sameHitCheck(state: any, position: Vector3, radius: number): (obstacle: any) -> boolean
		local memory = state.hitMemory
		hitRules.forget(memory, function(obstacle: any): number?
			return deps.gapTo(obstacle, position, radius)
		end)
		return function(obstacle: any): boolean
			return memory[obstacle] == true
		end
	end

	local function noteOutcome(
		state: any,
		outcome: any,
		counted: boolean,
		position: Vector3,
		root: BasePart?,
		now: number
	)
		hitRules.remember(state.hitMemory, outcome.contacts)
		state.sameHits += #outcome.repeats
		local touched = outcome.touches[1]
		if touched == nil then
			return
		end
		local result = if counted then "hit" elseif #outcome.repeats > 0 then "sameHit" else "protected"
		state.lastTouch = result
		if state.rebound == nil then
			state.rebound = hitRules.startWatch(now, touched, result)
		end
		if deps.verbose then
			local diameter = state.part.Size.X
			local beyond = beyondHold(position, root, diameter)
			local where = `ball={show(position)} character={show(if root then root.Position else nil)}`
			local sizes = `beyondHold={number(beyond)} diameter={number(diameter)}`
			local counts = `collisions={state.collisions} sameHits={state.sameHits}`
			print(
				`[BallService] {state.player.Name} obstacle touch obstacle={nameOf(touched)} result={result} {where} {sizes} {counts}`
			)
		end
	end

	local function finish(state: any, watch: any)
		state.rebound = nil
		local summary = hitRules.summarize(watch)
		state.reboundStuds = round(summary.studs, 2)
		state.reboundSeconds = round(summary.seconds, 2)
		state.reboundWithin = summary.within
		if deps.verbose then
			local atMax = watch.atMax or {}
			local measured = `maxBeyondHold={number(summary.studs)} backAfter={number(summary.seconds)}`
			local limit = `limit={config.ReboundMaxStuds}/{config.ReboundMaxSeconds} within={summary.within}`
			local where = `ballAtMax={show(atMax.ball)} characterAtMax={show(atMax.character)}`
			print(
				`[BallService] {state.player.Name} rebound obstacle={nameOf(watch.obstacle)} result={watch.result} {measured} {limit} {where}`
			)
		end
	end

	local function step(state: any, position: Vector3, root: BasePart?, now: number, elapsed: number)
		local watch = state.rebound
		if watch == nil then
			return
		end
		local diameter = state.part.Size.X
		local beyond = beyondHold(position, root, diameter)
		local character = if root then root.Position else nil
		if beyond ~= nil then
			hitRules.stepWatch(watch, now, beyond, { ball = position, character = character })
		end
		if deps.verbose and deps.isTracing() then
			local moved = Vector3.new(position.X - state.lastPosition.X, 0, position.Z - state.lastPosition.Z)
			local speed = if elapsed > 0 then moved.Magnitude / elapsed else 0
			local gap = deps.gapTo(watch.obstacle, position, diameter / 2)
			local where = `ball={show(position)} character={show(character)}`
			local measured = `beyondHold={number(beyond)} speed={number(speed)} gap={number(gap)}`
			print(`[BallService] {state.player.Name} hit trace t={number(now - watch.startedAt)} {where} {measured}`)
		end
		if hitRules.isWatchOver(watch, now) then
			finish(state, watch)
		end
	end

	return table.freeze({
		sameHitCheck = sameHitCheck,
		noteOutcome = noteOutcome,
		step = step,
	})
end

return table.freeze(AfterHitModule)

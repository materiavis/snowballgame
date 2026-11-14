--!strict
-- Pure rules for what follows an obstacle touch (issue #97, ADR 0002 "After a hit"). No
-- Instances, so `lune run tests` loads it; BallStep binds it to Config.Ball.
--
-- Same hit (D2): one hit with the character pushing on costs at most one collision. After a
-- touch the obstacle stays in the memory until the gap between the ball's surface and that
-- obstacle has reached CollisionSeparationStuds. A touch of a remembered obstacle is the same
-- hit (ObstacleRules.evaluate). Distance instead of time: a rebound that wobbles back after a
-- few seconds is still the same hit, and only leaving the obstacle clearly starts a new one.
--
-- Rebound watch (D1, Studio diagnostics): after a touch, how far the ball centre gets beyond
-- the hold distance from the character on the ground plane within ReboundWatchTime, and how
-- long it stays more than ReboundSettleStuds beyond it, checked against the agreed limit.

export type HitConfig = {
	CollisionSeparationStuds: number,
	ReboundMaxStuds: number,
	ReboundMaxSeconds: number,
	ReboundSettleStuds: number,
	ReboundWatchTime: number,
}

-- Obstacles that still belong to the last hit (opaque keys: BaseParts in the game).
export type Memory = { [any]: boolean }

export type Watch = {
	startedAt: number,
	obstacle: any,
	result: string, -- "hit", "sameHit" or "protected"
	maxBeyond: number, -- studs beyond the hold distance, at least 0
	lastOutAt: number?, -- last sample more than ReboundSettleStuds beyond the hold distance
	atMax: any, -- caller's payload of the sample with maxBeyond (positions for the log)
}

export type Summary = {
	studs: number,
	seconds: number,
	within: boolean,
}

export type HitRules = {
	forget: (memory: Memory, gapOf: (obstacle: any) -> number?) -> (),
	remember: (memory: Memory, contacts: { [any]: boolean }) -> (),
	startWatch: (now: number, obstacle: any, result: string) -> Watch,
	stepWatch: (watch: Watch, now: number, beyond: number, payload: any) -> (),
	isWatchOver: (watch: Watch, now: number) -> boolean,
	summarize: (watch: Watch) -> Summary,
}

local HitRulesModule = {}

function HitRulesModule.new(config: HitConfig): HitRules
	-- Drops every remembered obstacle the ball has clearly left. `gapOf` returns the gap in
	-- studs between the ball's surface and the obstacle now, or nil when the obstacle is gone
	-- (knocked over, destroyed): a returning obstacle is a new one.
	local function forget(memory: Memory, gapOf: (obstacle: any) -> number?)
		for obstacle in memory do
			local gap = gapOf(obstacle)
			if gap == nil or gap >= config.CollisionSeparationStuds then
				memory[obstacle] = nil
			end
		end
	end

	-- Every obstacle touched in this sample belongs to the current hit.
	local function remember(memory: Memory, contacts: { [any]: boolean })
		for obstacle in contacts do
			memory[obstacle] = true
		end
	end

	local function startWatch(now: number, obstacle: any, result: string): Watch
		return {
			startedAt = now,
			obstacle = obstacle,
			result = result,
			maxBeyond = 0,
			lastOutAt = nil,
			atMax = nil,
		}
	end

	-- `beyond` is the ball centre's ground-plane distance from the character minus the hold
	-- distance; negative while the ball is closer (pressed between character and obstacle).
	local function stepWatch(watch: Watch, now: number, beyond: number, payload: any)
		if beyond > watch.maxBeyond or watch.atMax == nil then
			watch.maxBeyond = math.max(beyond, watch.maxBeyond)
			watch.atMax = payload
		end
		if beyond > config.ReboundSettleStuds then
			watch.lastOutAt = now
		end
	end

	local function isWatchOver(watch: Watch, now: number): boolean
		return now - watch.startedAt >= config.ReboundWatchTime
	end

	local function summarize(watch: Watch): Summary
		local lastOutAt = watch.lastOutAt
		local seconds = if lastOutAt then lastOutAt - watch.startedAt else 0
		return {
			studs = watch.maxBeyond,
			seconds = seconds,
			within = watch.maxBeyond <= config.ReboundMaxStuds and seconds <= config.ReboundMaxSeconds,
		}
	end

	return table.freeze({
		forget = forget,
		remember = remember,
		startWatch = startWatch,
		stepWatch = stepWatch,
		isWatchOver = isWatchOver,
		summarize = summarize,
	})
end

return table.freeze(HitRulesModule)

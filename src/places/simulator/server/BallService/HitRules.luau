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
-- long it stays more than ReboundSettleStuds beyond it (first to last sample out), checked
-- against the agreed limit. The time from the touch until it is back is reported as well
-- (`backAfter`); it also holds the time the ball spends pressed before it goes out (#97 round
-- 1: round 0 checked that time against the limit, unlike its documented definition).

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
	firstOutAt: number?, -- first sample more than ReboundSettleStuds beyond the hold distance
	lastOutAt: number?, -- last such sample
	outAtEnd: boolean, -- the latest sample was out
	atMax: any, -- caller's payload of the sample with maxBeyond (positions for the log)
}

export type Summary = {
	studs: number,
	seconds: number, -- out: first to last sample more than ReboundSettleStuds beyond
	backAfter: number, -- from the touch to the last sample out (0 if never out)
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
			firstOutAt = nil,
			lastOutAt = nil,
			outAtEnd = false,
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
		local out = beyond > config.ReboundSettleStuds
		if out then
			watch.firstOutAt = watch.firstOutAt or now
			watch.lastOutAt = now
		end
		watch.outAtEnd = out
	end

	local function isWatchOver(watch: Watch, now: number): boolean
		return now - watch.startedAt >= config.ReboundWatchTime
	end

	-- A ball still out at the end of the watch is not back, whatever the span so far.
	local function summarize(watch: Watch): Summary
		local firstOutAt, lastOutAt = watch.firstOutAt, watch.lastOutAt
		local seconds = if firstOutAt and lastOutAt then lastOutAt - firstOutAt else 0
		local backAfter = if lastOutAt then lastOutAt - watch.startedAt else 0
		return {
			studs = watch.maxBeyond,
			seconds = seconds,
			backAfter = backAfter,
			within = watch.maxBeyond <= config.ReboundMaxStuds
				and seconds <= config.ReboundMaxSeconds
				and not watch.outAtEnd,
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

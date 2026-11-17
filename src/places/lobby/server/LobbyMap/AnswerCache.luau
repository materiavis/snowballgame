--!strict
-- Caches yes/no answers of a slow web call per player (group membership, VIP pass; ADR 0015).
-- Pure; `query` may yield. A yes is kept for the session (nobody loses group membership or a
-- pass in a way that matters within one Lobby visit), a no is asked again after `recheck`
-- seconds (the player may join the group or buy the pass meanwhile), and a failed call (nil)
-- is never kept.

export type Cache = {
	get: (userId: number) -> boolean?,
	forget: (userId: number) -> (),
}

local AnswerCache = {}

function AnswerCache.new(query: (userId: number) -> boolean?, recheck: number, now: () -> number): Cache
	local cached: { [number]: { answer: boolean, at: number } } = {}

	local function get(userId: number): boolean?
		local entry = cached[userId]
		if entry and (entry.answer or now() - entry.at < recheck) then
			return entry.answer
		end
		local answer = query(userId)
		if answer == nil then
			cached[userId] = nil
		else
			cached[userId] = { answer = answer, at = now() }
		end
		return answer
	end

	return table.freeze({
		get = get,
		forget = function(userId: number)
			cached[userId] = nil
		end,
	})
end

return table.freeze(AnswerCache)

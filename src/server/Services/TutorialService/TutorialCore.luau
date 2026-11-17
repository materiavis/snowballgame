--!strict
-- The onboarding rules (concept 10.1, #42, ADR 0017). Pure: works on the live profile table
-- `tutorial` (schema v1) and on plain numbers, so `lune run tests` checks every rule.
--
-- State per hint: done (saved in the profile, never unset outside the Studio reset) and showing
-- (this session only). A hint shows when its Place matches, it is not done, every hint it
-- Requires is done, its condition holds and its channel is free. Once it shows it keeps its
-- channel until it is done, even if its condition goes away for a moment (a MAX ball hit by an
-- obstacle, Coins spent), so no hint ever appears twice.

export type Config = {
	Order: { string },
	Hints: { [string]: { Place: string, Channel: string, Requires: { string } } },
	ClientReportable: { string },
	MultiArrowHint: string,
	MoveDoneDistance: number,
	MaxStepPerCheck: number,
}

export type Showing = { [string]: string } -- channel -> hint id

export type Core = {
	isDone: (tutorial: any, id: string) -> boolean,
	markDone: (tutorial: any, id: string) -> boolean,
	doneList: (tutorial: any) -> { string },
	reset: (tutorial: any) -> boolean,
	select: (place: string, tutorial: any, eligible: { [string]: boolean }, showing: Showing) -> (Showing, { string }),
	checkReport: (id: any, active: { string }) -> (boolean, string?),
	walk: (walked: number, fromX: number?, fromZ: number?, toX: number, toZ: number) -> number,
	moved: (walked: number) -> boolean,
}

local TutorialCore = {}

local function isTable(value: any): boolean
	return type(value) == "table"
end

-- Distance from a point to a box, both in the box's own frame (the point is box-local, the box
-- is centred at the origin with full sizes sx, sy, sz). 0 inside.
function TutorialCore.boxDistance(lx: number, ly: number, lz: number, sx: number, sy: number, sz: number): number
	local dx = math.max(math.abs(lx) - sx / 2, 0)
	local dy = math.max(math.abs(ly) - sy / 2, 0)
	local dz = math.max(math.abs(lz) - sz / 2, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function TutorialCore.new(config: Config): Core
	local known: { [string]: boolean } = {}
	for _, id in config.Order do
		known[id] = true
	end
	local reportable: { [string]: boolean } = {}
	for _, id in config.ClientReportable do
		reportable[id] = true
	end

	local function isDone(tutorial: any, id: string): boolean
		if not isTable(tutorial) then
			return false
		end
		if id == config.MultiArrowHint then
			return tutorial.seenMultiArrow == true
		end
		return isTable(tutorial.hints) and tutorial.hints[id] == true
	end

	-- Sets a known hint to done. Returns true when it changed. Never sets anything to false.
	local function markDone(tutorial: any, id: string): boolean
		if not isTable(tutorial) or not known[id] or isDone(tutorial, id) then
			return false
		end
		if id == config.MultiArrowHint then
			tutorial.seenMultiArrow = true
			return true
		end
		if not isTable(tutorial.hints) then
			-- Not a table can only be a broken value; a set with one entry replaces it.
			tutorial.hints = {}
		end
		tutorial.hints[id] = true
		return true
	end

	local function doneList(tutorial: any): { string }
		local out: { string } = {}
		for _, id in config.Order do
			if isDone(tutorial, id) then
				table.insert(out, id)
			end
		end
		return out
	end

	-- Studio reset: every hint of this module unseen again. seenSingleArrow belongs to
	-- PortalService (LobbyStudioReset, ADR 0015) and is left alone.
	local function reset(tutorial: any): boolean
		if not isTable(tutorial) then
			return false
		end
		tutorial.hints = {}
		tutorial.seenMultiArrow = false
		tutorial.firstMatchHints = false
		return true
	end

	local function requiresDone(tutorial: any, id: string): boolean
		for _, required in config.Hints[id].Requires do
			if not isDone(tutorial, required) then
				return false
			end
		end
		return true
	end

	-- The new channel map and the showing ids in Order. Without a profile nothing shows: a failed
	-- load must never look like a new player.
	local function select(
		place: string,
		tutorial: any,
		eligible: { [string]: boolean },
		showing: Showing
	): (Showing, { string })
		local nextShowing: Showing = {}
		local active: { string } = {}
		if not isTable(tutorial) then
			return nextShowing, active
		end
		for channel, id in showing do
			local hint = config.Hints[id]
			if hint and hint.Place == place and not isDone(tutorial, id) then
				nextShowing[channel] = id
			end
		end
		for _, id in config.Order do
			local hint = config.Hints[id]
			if
				nextShowing[hint.Channel] == nil
				and hint.Place == place
				and not isDone(tutorial, id)
				and eligible[id] == true
				and requiresDone(tutorial, id)
			then
				nextShowing[hint.Channel] = id
			end
		end
		for _, id in config.Order do
			if nextShowing[config.Hints[id].Channel] == id then
				table.insert(active, id)
			end
		end
		return nextShowing, active
	end

	-- A client report is accepted only for a reportable id that is showing for that player.
	local function checkReport(id: any, active: { string }): (boolean, string?)
		if type(id) ~= "string" or not reportable[id] then
			return false, "NotReportable"
		end
		if table.find(active, id) == nil then
			return false, "NotActive"
		end
		return true, nil
	end

	-- Adds one check's horizontal step. The first check (no previous position) and steps longer
	-- than MaxStepPerCheck (teleport, respawn, VIP push) add nothing.
	local function walk(walked: number, fromX: number?, fromZ: number?, toX: number, toZ: number): number
		if fromX == nil or fromZ == nil then
			return walked
		end
		local dx, dz = toX - fromX, toZ - fromZ
		local step = math.sqrt(dx * dx + dz * dz)
		if step ~= step or step > config.MaxStepPerCheck then
			return walked
		end
		return walked + step
	end

	local function moved(walked: number): boolean
		return walked >= config.MoveDoneDistance
	end

	return table.freeze({
		isDone = isDone,
		markDone = markDone,
		doneList = doneList,
		reset = reset,
		select = select,
		checkReport = checkReport,
		walk = walk,
		moved = moved,
	})
end

return table.freeze(TutorialCore)

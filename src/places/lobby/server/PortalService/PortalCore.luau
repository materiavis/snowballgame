--!strict
-- Per-player portal state (concept 7.1, 6.5; ADR 0015). Pure: the clock is injected and every
-- input comes from the server's own view, so a headless spec runs the whole rule.
--
-- step(userId, input) is called every Config.Lobby.PortalCheckInterval with:
--   inside      the PortalMode whose walk-in volume holds the character root, or nil
--   locked      DataService.IsPortalLocked (profile not loaded, concept 6.5)
--   travelling  TravelService.IsTraveling (a travel started elsewhere)
--
-- States:
--   Idle        outside every portal
--   Closed      inside a closed portal (Vertical Slice: Multiplayer); nothing starts
--   Locked      inside an open portal while the profile is not loaded; nothing starts
--   Busy        inside an open portal while another travel runs; nothing starts
--   Countdown   inside an open portal; travel at endsAt, walking out cancels
--   Travelling  the portal's travel runs (until travelFinished)
--   WaitExit    the travel ended and the character is still inside: leave first, so a stub
--               success in Studio or a failed teleport never starts the next countdown at once

export type State = "Idle" | "Closed" | "Locked" | "Busy" | "Countdown" | "Travelling" | "WaitExit"

export type Input = { inside: string?, locked: boolean, travelling: boolean }

export type Result = {
	state: State,
	mode: string, -- "" outside
	endsAt: number, -- 0 unless Countdown
	changed: boolean, -- state, mode or endsAt changed in this step
	travel: boolean, -- true once: start the travel of `mode` now
	event: string?, -- for the log: Started, Cancelled, CancelledLocked, Closed, Locked, Busy, Travel
}

export type Deps = {
	countdown: number,
	closedModes: { [string]: boolean },
	now: () -> number,
}

type Entry = { state: State, mode: string, endsAt: number }

local PortalCore = {}

function PortalCore.new(deps: Deps)
	local entries: { [number]: Entry } = {}
	local core = {}

	local function entryOf(userId: number): Entry
		local entry = entries[userId]
		if entry == nil then
			entry = { state = "Idle", mode = "", endsAt = 0 }
			entries[userId] = entry
		end
		return entry
	end

	local function set(
		entry: Entry,
		state: State,
		mode: string,
		endsAt: number,
		event: string?,
		travel: boolean
	): Result
		local changed = entry.state ~= state or entry.mode ~= mode or entry.endsAt ~= endsAt
		entry.state, entry.mode, entry.endsAt = state, mode, endsAt
		return {
			state = state,
			mode = mode,
			endsAt = endsAt,
			changed = changed,
			travel = travel,
			event = if changed then event else nil,
		}
	end

	function core.step(userId: number, input: Input): Result
		local entry = entryOf(userId)
		local inside = input.inside

		if entry.state == "Travelling" then
			return set(entry, "Travelling", entry.mode, 0, nil, false)
		end
		if entry.state == "WaitExit" and inside ~= nil then
			return set(entry, "WaitExit", entry.mode, 0, nil, false)
		end
		if inside == nil then
			local event = if entry.state == "Countdown" then "Cancelled" else nil
			return set(entry, "Idle", "", 0, event, false)
		end
		if deps.closedModes[inside] then
			return set(entry, "Closed", inside, 0, "Closed", false)
		end
		if input.locked then
			local event = if entry.state == "Countdown" then "CancelledLocked" else "Locked"
			return set(entry, "Locked", inside, 0, event, false)
		end
		if input.travelling then
			local event = if entry.state == "Countdown" then "CancelledBusy" else "Busy"
			return set(entry, "Busy", inside, 0, event, false)
		end
		if entry.state == "Countdown" and entry.mode == inside then
			if deps.now() >= entry.endsAt then
				return set(entry, "Travelling", inside, 0, "Travel", true)
			end
			return set(entry, "Countdown", inside, entry.endsAt, nil, false)
		end
		return set(entry, "Countdown", inside, deps.now() + deps.countdown, "Started", false)
	end

	-- The portal's travel ended (any outcome). The character must leave before the next one.
	function core.travelFinished(userId: number): Result
		local entry = entryOf(userId)
		return set(entry, "WaitExit", entry.mode, 0, "Finished", false)
	end

	-- Seconds left in the countdown, 0 when not counting.
	function core.remaining(userId: number): number
		local entry = entries[userId]
		if entry == nil or entry.state ~= "Countdown" then
			return 0
		end
		return math.max(0, entry.endsAt - deps.now())
	end

	function core.get(userId: number): (State, string)
		local entry = entries[userId]
		if entry == nil then
			return "Idle", ""
		end
		return entry.state, entry.mode
	end

	function core.forget(userId: number)
		entries[userId] = nil
	end

	return table.freeze(core)
end

return table.freeze(PortalCore)

--!strict
-- Player counts above the portals (concept 7.1; ADR 0015). Every PortalPlayerCountRefresh the
-- server reads each mode's count from PresenceStore and writes `PlayerCount` and
-- `PlayerCountAt` (Unix time of this refresh) on every bound portal Model of that mode. The
-- client only shows the attribute. A failed read keeps the last value and its time, so a stale
-- label is visible in the diagnostic instead of jumping to 0.
--
-- Sources: Singleplayer = players on public Simulator servers (their presence refresh writes
-- the count, PresenceStore). Multiplayer has no servers yet; nothing writes its entry, so it
-- shows 0 until matchmaking (7.14) publishes Arena counts with PresenceStore.SetModeCount.

export type Options = {
	modes: { string },
	refresh: number,
	getCount: (mode: string) -> number?,
	portalsOf: (mode: string) -> { Model },
	countAttribute: string,
	atAttribute: string,
	now: () -> number,
	wait: (seconds: number) -> (),
	log: (message: string) -> (),
}

export type Counts = {
	-- Writes the last known count onto a portal that just bound.
	apply: (portal: Model, mode: string) -> (),
	refreshNow: () -> (),
	run: () -> (),
	lastRefresh: () -> number,
}

local PlayerCounts = {}

function PlayerCounts.new(options: Options): Counts
	local known: { [string]: number } = {}
	local knownAt: { [string]: number } = {}
	local last = 0

	local function apply(portal: Model, mode: string)
		portal:SetAttribute(options.countAttribute, known[mode] or 0)
		portal:SetAttribute(options.atAttribute, knownAt[mode] or 0)
	end

	local function refreshNow()
		for _, mode in options.modes do
			local count = options.getCount(mode)
			if count ~= nil then
				if count ~= known[mode] then
					options.log(`{mode} players {known[mode] or 0} -> {count}`)
				end
				known[mode] = count
				knownAt[mode] = options.now()
			end
			for _, portal in options.portalsOf(mode) do
				apply(portal, mode)
			end
		end
		last = options.now()
	end

	-- Start to start, so the gap between two refreshes stays at `refresh` however long a
	-- MemoryStore read takes (up to the read's own timeout).
	local function run()
		while true do
			local started = options.now()
			refreshNow()
			options.wait(math.max(0, options.refresh - (options.now() - started)))
		end
	end

	return table.freeze({
		apply = apply,
		refreshNow = refreshNow,
		run = run,
		lastRefresh = function(): number
			return last
		end,
	})
end

return table.freeze(PlayerCounts)

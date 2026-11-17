--!strict
-- Order and timing of the centre pop-ups (concept 10.2, #90). Pure: the clock is passed in, so
-- tests drive it by hand. A pop-up shows for `duration` seconds; pop-ups that arrive meanwhile
-- wait in order, at most `maxQueued` of them (the oldest waiting one is dropped first).

export type PopupQueue<T> = {
	-- Adds an entry. Returns true if it shows at once.
	push: (entry: T, now: number) -> boolean,
	-- The entry showing at `now` (advancing past expired ones), or nil.
	current: (now: number) -> T?,
	-- When the showing entry ends, or nil if nothing shows.
	endsAt: () -> number?,
	waiting: () -> number,
}

local PopupQueue = {}

function PopupQueue.new<T>(duration: number, maxQueued: number): PopupQueue<T>
	assert(duration > 0, "PopupQueue: duration must be positive")
	assert(maxQueued >= 0 and maxQueued % 1 == 0, "PopupQueue: maxQueued must be a whole number >= 0")

	local showing: T? = nil
	local showingEnds = 0
	local queue: { T } = {}

	local function advance(now: number)
		while showing ~= nil and now >= showingEnds do
			showing = table.remove(queue, 1)
			-- The next one gets its full time from when it actually appears.
			showingEnds = now + duration
		end
	end

	local popups = {}

	function popups.push(entry: T, now: number): boolean
		advance(now)
		if showing == nil then
			showing = entry
			showingEnds = now + duration
			return true
		end
		table.insert(queue, entry)
		while #queue > maxQueued do
			table.remove(queue, 1)
		end
		return false
	end

	function popups.current(now: number): T?
		advance(now)
		return showing
	end

	function popups.endsAt(): number?
		return if showing ~= nil then showingEnds else nil
	end

	function popups.waiting(): number
		return #queue
	end

	return table.freeze(popups) :: any
end

return table.freeze(PopupQueue)

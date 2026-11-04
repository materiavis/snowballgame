--!strict
-- Counts accepted and dropped remote calls per remote. Pure.
-- Subscribers get every event, so the analytics service (#43) can attach later without
-- touching the guard. A subscriber that errors is isolated, because counting must never
-- break a remote call.

export type Reason = "Rate" | "Arity" | "Args" | "Auth" | "NoHandler"

export type Event = {
	remote: string,
	outcome: "Accepted" | "Rejected" | "HandlerError",
	reason: Reason?,
	detail: string?,
	player: any,
}

export type Counts = {
	accepted: number,
	rejected: number,
	handlerErrors: number,
	byReason: { [string]: number },
}

export type Listener = (event: Event) -> ()

export type Stats = {
	accepted: (self: Stats, remote: string, player: any) -> (),
	rejected: (self: Stats, remote: string, reason: Reason, detail: string, player: any) -> (),
	handlerError: (self: Stats, remote: string, detail: string, player: any) -> (),
	get: (self: Stats, remote: string) -> Counts,
	totalRejected: (self: Stats) -> number,
	subscribe: (self: Stats, listener: Listener) -> (),
	_counts: { [string]: Counts },
	_listeners: { Listener },
}

local Stats = {}
Stats.__index = Stats

function Stats.new(): Stats
	local self = { _counts = {}, _listeners = {} }
	return (setmetatable(self, Stats) :: any) :: Stats
end

local function countsFor(self: Stats, remote: string): Counts
	local counts = self._counts[remote]
	if counts == nil then
		counts = { accepted = 0, rejected = 0, handlerErrors = 0, byReason = {} }
		self._counts[remote] = counts
	end
	return counts
end

local function emit(self: Stats, event: Event)
	for _, listener in self._listeners do
		pcall(listener, event)
	end
end

function Stats.accepted(self: Stats, remote: string, player: any)
	local counts = countsFor(self, remote)
	counts.accepted += 1
	emit(self, { remote = remote, outcome = "Accepted", player = player })
end

function Stats.rejected(self: Stats, remote: string, reason: Reason, detail: string, player: any)
	local counts = countsFor(self, remote)
	counts.rejected += 1
	counts.byReason[reason] = (counts.byReason[reason] or 0) + 1
	emit(self, { remote = remote, outcome = "Rejected", reason = reason, detail = detail, player = player })
end

function Stats.handlerError(self: Stats, remote: string, detail: string, player: any)
	local counts = countsFor(self, remote)
	counts.handlerErrors += 1
	emit(self, { remote = remote, outcome = "HandlerError", detail = detail, player = player })
end

-- Returns a copy, so callers cannot change the live counters.
function Stats.get(self: Stats, remote: string): Counts
	local counts = countsFor(self, remote)
	return {
		accepted = counts.accepted,
		rejected = counts.rejected,
		handlerErrors = counts.handlerErrors,
		byReason = table.clone(counts.byReason),
	}
end

function Stats.totalRejected(self: Stats): number
	local total = 0
	for _, counts in self._counts do
		total += counts.rejected
	end
	return total
end

function Stats.subscribe(self: Stats, listener: Listener)
	table.insert(self._listeners, listener)
end

return table.freeze(Stats)

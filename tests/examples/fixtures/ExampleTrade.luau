--!strict
-- EXAMPLE FIXTURE, NOT GAME CODE. A minimal two-party swap state machine that shows how
-- trade invariants are tested (concept 7.23). The real trade service, its limits and its
-- ledger come with the pet-trading feature.

export type Side = "A" | "B"
export type State = "Open" | "Committed" | "Aborted"
export type ItemSet = { [string]: true }

export type Trade = {
	state: State,
	inventories: { A: ItemSet, B: ItemSet },
	offers: { A: ItemSet, B: ItemSet },
	ready: { A: boolean, B: boolean },
}

-- Called between commit steps so tests can inject a failure (an error) at any point.
export type StepHook = (step: string) -> ()

local ExampleTrade = {}

local function other(side: Side): Side
	return if side == "A" then "B" else "A"
end

local function copySet(set: ItemSet): ItemSet
	local copy: ItemSet = {}
	for uid in set do
		copy[uid] = true
	end
	return copy
end

function ExampleTrade.new(itemsA: { string }, itemsB: { string }): Trade
	local function toSet(items: { string }): ItemSet
		local set: ItemSet = {}
		for _, uid in items do
			set[uid] = true
		end
		return set
	end
	return {
		state = "Open",
		inventories = { A = toSet(itemsA), B = toSet(itemsB) },
		offers = { A = {}, B = {} },
		ready = { A = false, B = false },
	}
end

-- Any change to the offer clears both ready flags, so nobody can swap items after the
-- other side has agreed.
local function clearReady(trade: Trade)
	trade.ready.A = false
	trade.ready.B = false
end

function ExampleTrade.offer(trade: Trade, side: Side, uid: string): (boolean, string?)
	if trade.state ~= "Open" then
		return false, "closed"
	end
	if not trade.inventories[side][uid] then
		return false, "not owned"
	end
	if trade.offers[side][uid] then
		return false, "already offered"
	end
	trade.offers[side][uid] = true
	clearReady(trade)
	return true
end

function ExampleTrade.withdraw(trade: Trade, side: Side, uid: string): (boolean, string?)
	if trade.state ~= "Open" then
		return false, "closed"
	end
	if not trade.offers[side][uid] then
		return false, "not offered"
	end
	trade.offers[side][uid] = nil
	clearReady(trade)
	return true
end

function ExampleTrade.setReady(trade: Trade, side: Side, ready: boolean): (boolean, string?)
	if trade.state ~= "Open" then
		return false, "closed"
	end
	trade.ready[side] = ready
	return true
end

-- Builds both new inventories on copies and swaps them in with one assignment, so an
-- error at any hooked step leaves the trade exactly as it was before the commit.
function ExampleTrade.commit(trade: Trade, hook: StepHook?): (boolean, string?)
	if trade.state ~= "Open" then
		return false, "closed"
	end
	if not (trade.ready.A and trade.ready.B) then
		return false, "not ready"
	end

	local step: StepHook = hook or function() end
	local nextInventories = { A = copySet(trade.inventories.A), B = copySet(trade.inventories.B) }
	step("copied")
	for _, side: Side in { "A" :: Side, "B" :: Side } do
		for uid in trade.offers[side] do
			nextInventories[side][uid] = nil
			step("removed")
			nextInventories[other(side)][uid] = true
			step("added")
		end
	end
	step("beforeSwap")

	trade.inventories = nextInventories
	trade.state = "Committed"
	return true
end

function ExampleTrade.abort(trade: Trade): (boolean, string?)
	if trade.state ~= "Open" then
		return false, "closed"
	end
	trade.state = "Aborted"
	return true
end

return table.freeze(ExampleTrade)

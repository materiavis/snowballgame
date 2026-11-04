--!strict
-- Example: randomised state-machine test (concept 7.23: 1,000 automatic trades, no pet
-- duplicated or lost). Runs random operation sequences, injects commit failures, and checks
-- the conservation invariant after every single step.

local T = require("../TestKit")
local SeededRandom = require("../helpers/SeededRandom")
local ExampleTrade = require("./fixtures/ExampleTrade")

type Trade = ExampleTrade.Trade
type Side = ExampleTrade.Side

local TRADES = 1000
local MAX_ITEMS_PER_SIDE = 8
local MAX_STEPS_PER_TRADE = 30
local SEED = 7231000

local SIDES: { Side } = { "A", "B" }

local function snapshot(trade: Trade): { [string]: Side }
	local owners: { [string]: Side } = {}
	for _, side in SIDES do
		for uid in trade.inventories[side] do
			owners[uid] = side
		end
	end
	return owners
end

local function sameOwners(a: { [string]: Side }, b: { [string]: Side }): boolean
	for uid, side in a do
		if b[uid] ~= side then
			return false
		end
	end
	for uid in b do
		if a[uid] == nil then
			return false
		end
	end
	return true
end

-- Every uid that entered the trade is owned by exactly one side, and nothing new appeared.
local function checkConservation(trade: Trade, allUids: { string }, context: string)
	local seen: { [string]: number } = {}
	for _, side in SIDES do
		for uid in trade.inventories[side] do
			seen[uid] = (seen[uid] or 0) + 1
		end
	end
	local known: { [string]: boolean } = {}
	for _, uid in allUids do
		known[uid] = true
		local count = seen[uid] or 0
		if count == 0 then
			error(`{context}: {uid} was lost`, 2)
		elseif count > 1 then
			error(`{context}: {uid} was duplicated`, 2)
		end
	end
	for uid in seen do
		if not known[uid] then
			error(`{context}: {uid} appeared from nowhere`, 2)
		end
	end
	if trade.state == "Open" then
		for _, side in SIDES do
			for uid in trade.offers[side] do
				if not trade.inventories[side][uid] then
					error(`{context}: side {side} offers {uid} it does not own`, 2)
				end
			end
		end
	end
end

local function pickFrom(rng: SeededRandom.Generator, set: { [string]: true }): string?
	local items: { string } = {}
	for uid in set do
		table.insert(items, uid)
	end
	if #items == 0 then
		return nil
	end
	-- Pairs order is not stable across runs; sorting keeps the seeded run reproducible.
	table.sort(items)
	return items[rng.nextInteger(1, #items)]
end

return T.suite("Example trade state machine", function(test)
	test("1,000 randomised trades never duplicate or lose an item", function()
		local rng = SeededRandom.new(SEED)
		local nextUid = 0
		local stats = { committed = 0, aborted = 0, injectedFailures = 0, rejected = 0 }

		for tradeIndex = 1, TRADES do
			local itemsA, itemsB, allUids = {}, {}, {}
			for _, list in { itemsA, itemsB } do
				for _ = 1, rng.nextInteger(0, MAX_ITEMS_PER_SIDE) do
					nextUid += 1
					local uid = `uid{nextUid}`
					table.insert(list, uid)
					table.insert(allUids, uid)
				end
			end

			local trade = ExampleTrade.new(itemsA, itemsB)
			for stepIndex = 1, rng.nextInteger(1, MAX_STEPS_PER_TRADE) do
				local context = `trade {tradeIndex} step {stepIndex}`
				local side = SIDES[rng.nextInteger(1, 2)]
				local op = rng.nextInteger(1, 20)

				if op <= 6 then
					local uid = pickFrom(rng, trade.inventories[side])
					if uid then
						ExampleTrade.offer(trade, side, uid)
					end
				elseif op <= 8 then
					-- Offering the other side's item, or one that does not exist, must be refused.
					local foreign = pickFrom(rng, trade.inventories[if side == "A" then "B" else "A"])
					local before = snapshot(trade)
					local ok = ExampleTrade.offer(trade, side, foreign or "missing")
					T.isTrue(not ok or trade.state ~= "Open", `{context}: foreign offer was accepted`)
					T.isTrue(sameOwners(before, snapshot(trade)), `{context}: rejected offer changed owners`)
					stats.rejected += 1
				elseif op <= 10 then
					local uid = pickFrom(rng, trade.offers[side])
					if uid then
						ExampleTrade.withdraw(trade, side, uid)
					end
				elseif op <= 14 then
					ExampleTrade.setReady(trade, side, rng.nextInteger(1, 4) > 1)
				elseif op <= 19 then
					local before = snapshot(trade)
					local expectedOwners = table.clone(before)
					for _, offerSide in SIDES do
						for uid in trade.offers[offerSide] do
							expectedOwners[uid] = if offerSide == "A" then "B" else "A"
						end
					end
					local wasCommittable = trade.state == "Open" and trade.ready.A and trade.ready.B

					-- A quarter of commits fail at a random internal step, like a crash mid-swap.
					local failAt = if rng.nextInteger(1, 4) == 1 then rng.nextInteger(1, 6) else nil
					local stepCount = 0
					local called, ok = pcall(ExampleTrade.commit, trade, function()
						stepCount += 1
						if stepCount == failAt then
							error("injected failure")
						end
					end)

					if not called then
						stats.injectedFailures += 1
						T.equal(trade.state, "Open", `{context}: failed commit changed state`)
						T.isTrue(sameOwners(before, snapshot(trade)), `{context}: failed commit moved items`)
					elseif ok then
						stats.committed += 1
						T.isTrue(sameOwners(expectedOwners, snapshot(trade)), `{context}: wrong items moved`)
					else
						T.isTrue(not wasCommittable, `{context}: committable trade was refused`)
					end
				else
					if ExampleTrade.abort(trade) then
						stats.aborted += 1
					end
				end

				checkConservation(trade, allUids, context)
			end
		end

		-- A random walk that never reached a path proves nothing about that path.
		T.isTrue(stats.committed > 0, "no trade committed")
		T.isTrue(stats.aborted > 0, "no trade aborted")
		T.isTrue(stats.injectedFailures > 0, "no failure was injected")
		T.isTrue(stats.rejected > 0, "no invalid offer was tried")
	end)

	test("replaying commit or abort on a finished trade changes nothing", function()
		local trade = ExampleTrade.new({ "a1" }, { "b1" })
		ExampleTrade.offer(trade, "A", "a1")
		ExampleTrade.setReady(trade, "A", true)
		ExampleTrade.setReady(trade, "B", true)
		T.isTrue((ExampleTrade.commit(trade)), "first commit")

		local after = snapshot(trade)
		local ok, reason = ExampleTrade.commit(trade)
		T.equal(ok, false)
		T.equal(reason, "closed")
		T.equal((ExampleTrade.abort(trade)), false)
		T.isTrue(sameOwners(after, snapshot(trade)), "replay moved items")
		T.equal(after.a1, "B")
		T.equal(after.b1, "B")
	end)

	test("changing an offer clears both ready flags", function()
		local trade = ExampleTrade.new({ "a1", "a2" }, { "b1" })
		ExampleTrade.offer(trade, "A", "a1")
		ExampleTrade.setReady(trade, "A", true)
		ExampleTrade.setReady(trade, "B", true)
		ExampleTrade.offer(trade, "A", "a2")
		local ok, reason = ExampleTrade.commit(trade)
		T.equal(ok, false)
		T.equal(reason, "not ready")
	end)
end)

--!strict
-- Trade ledger access and global leaderboard stores (ADR 0003): encoding, write-on-autosave,
-- reads, and the ledger check-and-set the trade service (#49) builds on.

local T = require("../../TestKit")
local H = require("./Harness")
local GlobalStores = require("../../../src/server/Services/DataService/GlobalStores")

local SCALE = H.Config.LogScale

return T.suite("DataService/GlobalStores", function(test)
	test("Log encoding fits coins up to Sx in an integer and keeps the order", function()
		local sx = GlobalStores.encode("Log", 1e21, SCALE) :: number
		T.isTrue(sx < 2 ^ 63 and sx % 1 == 0, "integer below 2^63")
		T.equal(sx, math.floor(21 * SCALE))
		T.isTrue(
			(GlobalStores.encode("Log", 2e6, SCALE) :: number) > (GlobalStores.encode("Log", 1e6, SCALE) :: number)
		)
		T.near(
			GlobalStores.decode("Log", GlobalStores.encode("Log", 3.4e15, SCALE) :: number, SCALE),
			3.4e15,
			3.4e15 * 1e-5
		)
		T.equal(GlobalStores.encode("Log", 0, SCALE), 0)
		T.equal(GlobalStores.encode("Log", 0 / 0, SCALE), nil, "NaN rejected")
	end)

	test("Raw encoding stores whole numbers", function()
		T.equal(GlobalStores.encode("Raw", 12.7, SCALE), 12)
		T.equal(GlobalStores.encode("Raw", -3, SCALE), 0)
		T.equal(GlobalStores.encode("Raw", 2 ^ 60, SCALE), nil, "too large to be exact")
		T.equal(GlobalStores.decode("Raw", 12, SCALE), 12)
	end)

	test("board values are written on flush (autosave) only, newest value wins", function()
		local world = H.world()
		local server = H.server(world, "A")
		local store = world.service:GetOrderedDataStore(H.Config.Boards.TotalCoins.Store)
		T.equal(server.boards.queueBoardValue("TotalCoins", 7, 100), true)
		T.equal(server.boards.queueBoardValue("TotalCoins", 7, 1e18), true)
		T.equal(store:callCount("SetAsync"), 0, "nothing written before the flush")
		T.equal(server.boards.flushBoards(), 1)
		T.equal(store:GetAsync("7"), math.floor(18 * SCALE))
		T.equal(server.boards.flushBoards(), 0, "queue empty after a flush")
	end)

	test("a failed board write stays queued; disabled writes and bad input are refused", function()
		local world = H.world()
		local server = H.server(world, "A")
		local store = world.service:GetOrderedDataStore(H.Config.Boards.Wins.Store)
		server.boards.queueBoardValue("Wins", 7, 3)
		store:setFailing("SetAsync", true)
		local written, failed = server.boards.flushBoards()
		T.equal(written, 0)
		T.equal(failed, 1)
		store:setFailing("SetAsync", false)
		T.equal(server.boards.flushBoards(), 1)
		T.equal(store:GetAsync("7"), 3)

		T.equal(server.boards.queueBoardValue("Nope", 7, 1), false, "unknown board")
		T.equal(server.boards.queueBoardValue("Wins", 0, 1), false, "not a user id")
		T.equal(server.boards.queueBoardValue("Wins", 7, 0 / 0), false, "NaN")
		server.boards.setWritesEnabled(false)
		T.equal(server.boards.queueBoardValue("Wins", 7, 4), false, "writes off")
	end)

	test("getTop returns decoded entries, highest first", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.boards.queueBoardValue("TotalCoins", 1, 1e3)
		server.boards.queueBoardValue("TotalCoins", 2, 1e9)
		server.boards.queueBoardValue("TotalCoins", 3, 1e6)
		server.boards.flushBoards()
		local ok, top = server.boards.getTop("TotalCoins", 2)
		T.equal(ok, true)
		T.equal(#top, 2)
		T.equal(top[1].userId, 2)
		T.near(top[1].value, 1e9, 1e9 * 1e-5)
		T.equal(top[2].userId, 3)
	end)

	test("ledger: UpdateAsync check-and-set, first writer wins (abort racing commit)", function()
		local world = H.world()
		local server = H.server(world, "A")
		local function setIfEmpty(state: string)
			return function(old)
				if old ~= nil then
					return nil
				end
				return { state = state }
			end
		end
		local ok, entry = server.boards.updateLedgerEntry("t1", setIfEmpty("committed"))
		T.equal(ok, true)
		T.equal(entry.state, "committed")
		local ok2, entry2 = server.boards.updateLedgerEntry("t1", setIfEmpty("aborted"))
		T.equal(ok2, true)
		T.equal(entry2, nil, "the abort was cancelled")
		local _, read = server.boards.getLedgerEntry("t1")
		T.equal(read.state, "committed")

		T.equal((server.boards.updateLedgerEntry("", setIfEmpty("x"))), false, "empty id")
		T.equal((server.boards.getLedgerEntry(string.rep("x", 60))), false, "key too long")
	end)

	test("ledger: store errors are retried and then reported", function()
		local world = H.world()
		local server = H.server(world, "A")
		local ledger = world.service:GetDataStore(H.Config.LedgerStoreName)
		ledger:setFailing("UpdateAsync", true)
		local ok = server.boards.updateLedgerEntry("t2", function()
			return { state = "committed" }
		end)
		T.equal(ok, false)
		T.equal(ledger:callCount("UpdateAsync"), H.Config.StoreAttempts)
	end)
end)

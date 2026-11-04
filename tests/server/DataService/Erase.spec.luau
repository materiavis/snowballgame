--!strict
-- Right-to-erasure (concept 12.1, issue #26 AC6): profile and leaderboard entries go, and no
-- server writes the profile back afterwards.

local T = require("../../TestKit")
local H = require("./Harness")

local USER = H.USER

return T.suite("DataService erase", function(test)
	test("removes the profile and every leaderboard entry", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.getData(USER).sim.coins = 9
		server.core.release(USER, "Leave")
		for boardId in H.Config.Boards do
			server.boards.queueBoardValue(boardId, USER, 5)
		end
		server.boards.flushBoards()

		local ok, err = server.core.eraseUser(USER)
		T.equal(ok, true, err)
		T.equal(H.stored(world, USER), nil, "profile gone")
		for _, board in H.Config.Boards do
			T.equal(world.service:GetOrderedDataStore(board.Store):GetAsync(tostring(USER)), nil, board.Store)
		end

		local again = H.server(world, "B")
		again.core.load(USER)
		T.equal(again.core.getData(USER).sim.coins, 0, "a later join starts from defaults")
	end)

	test("refuses while the player has a session on this server, and bad ids", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		T.equal((server.core.eraseUser(USER)), false)
		T.isTrue(H.stored(world, USER) ~= nil)
		T.equal((server.core.eraseUser(0)), false)
		T.equal((server.core.eraseUser(1.5)), false)
	end)

	test("a server that still holds the erased player never writes the profile back", function()
		local world = H.world()
		local holder = H.server(world, "A")
		holder.core.load(USER)
		local admin = H.server(world, "Admin")
		T.equal(admin.core.eraseUser(USER), true)

		T.equal(holder.core.save(USER, "Autosave"), false)
		T.equal(holder.core.getStatus(USER), "Lost")
		T.equal(#holder.kicks, 1)
		holder.core.release(USER, "Leave")
		T.equal(H.stored(world, USER), nil)
	end)

	test("a store error is reported, not swallowed", function()
		local world = H.world()
		local server = H.server(world, "A")
		world.store:setFailing("RemoveAsync", true)
		local ok, err = server.core.eraseUser(USER)
		T.equal(ok, false)
		T.isTrue(string.find(err :: string, "injected") ~= nil, err)
	end)
end)

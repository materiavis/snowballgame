--!strict
-- Session lock between simulated servers sharing one fake store (issue #26 AC3, AC4; ADR 0003
-- rev 2): wait while fresh, renew on every save, steal only after LockTimeout, and a server
-- that lost its lock never writes again and kicks the player.

local T = require("../../TestKit")
local H = require("./Harness")

local USER = H.USER
local Config = H.Config

return T.suite("DataService session lock", function(test)
	test("AC3: a second server waits for a fresh lock and gets the first server's newest data", function()
		local world = H.world()
		local a = H.server(world, "A")
		a.core.load(USER)
		a.core.getData(USER).sim.coins = 1
		a.core.save(USER, "Autosave")

		local b = H.server(world, "B")
		local handedOver = false
		b.onWait = function()
			if not handedOver then
				handedOver = true
				T.equal(b.core.getStatus(USER), "Loading", "B waits, does not load defaults")
				-- A keeps playing during B's wait, then the player moves over (leave / teleport).
				a.core.getData(USER).sim.coins = 2
				T.equal(a.core.release(USER, "Leave"), true)
			end
		end
		T.equal(b.core.load(USER), "Loaded")
		T.isTrue(handedOver, "B waited at least once")
		T.equal(b.waits[1], Config.LockRetryInterval)
		T.equal(b.core.getData(USER).sim.coins, 2, "no loss: B has A's last state")
		T.isTrue(not H.logged(b, "took over"), "no steal while the lock was fresh")
		T.equal(H.stored(world, USER).lockServer, "B")
		T.equal(H.stored(world, USER).saveSeq, 2)

		b.core.getData(USER).sim.coins = 3
		b.core.save(USER, "Autosave")
		T.equal(H.stored(world, USER).saveSeq, 3, "saveSeq keeps growing across servers")
	end)

	test("AC4: every autosave renews lockTime, so a live server keeps its lock past LockTimeout", function()
		local world = H.world()
		local a = H.server(world, "A")
		a.core.load(USER)
		local elapsed = 0
		while elapsed <= Config.LockTimeout * 2 do
			world.clock.advance(Config.AutosaveInterval)
			elapsed += Config.AutosaveInterval
			T.equal(a.core.autosaveAll(), 1)
			T.equal(H.stored(world, USER).lockTime, world.clock.now(), "renewed in the same write")
		end

		local b = H.server(world, "B")
		b.onWait = function()
			b.core.release(USER, "Leave") -- the player gives up on B after one retry
		end
		T.equal(b.core.load(USER), "Released")
		T.equal(H.stored(world, USER).lockServer, "A", "B could not steal a renewed lock")
		T.equal(#a.kicks, 0)
	end)

	test("AC4: a lock just under LockTimeout is fresh; at LockTimeout it can be stolen", function()
		local world = H.world()
		local a = H.server(world, "A")
		a.core.load(USER)
		world.clock.advance(Config.LockTimeout - 1)

		local b = H.server(world, "B")
		b.onWait = function()
			T.equal(b.core.getStatus(USER), "Loading")
			T.equal(H.stored(world, USER).lockServer, "A", "not stolen while fresh")
		end
		T.equal(b.core.load(USER), "Loaded")
		T.equal(#b.waits, 1, "one retry was enough once the lock aged out")
		T.equal(H.stored(world, USER).lockServer, "B")
		T.isTrue(H.logged(b, "took over the stale lock of A"))
	end)

	test("AC4: the server that lost its lock never writes again and kicks the player", function()
		local world = H.world()
		local a = H.server(world, "A")
		a.core.load(USER)
		a.core.getData(USER).sim.coins = 10
		a.core.save(USER, "Autosave")

		-- A stalls past the timeout (e.g. a frozen server); B takes over and saves.
		world.clock.advance(Config.LockTimeout)
		local b = H.server(world, "B")
		b.core.load(USER)
		b.core.getData(USER).sim.coins = 50
		b.core.save(USER, "Autosave")
		local stolen = H.stored(world, USER)

		a.core.getData(USER).sim.coins = 11
		local ok, why = a.core.save(USER, "Autosave")
		T.equal(ok, false)
		T.equal(why, "LockLost")
		T.equal(a.core.getStatus(USER), "Lost")
		T.equal(#a.kicks, 1, "kicked once")
		T.equal(a.kicks[1].userId, USER)
		T.equal(a.kicks[1].message, Config.LockLostKickMessage)

		local updatesBefore = world.store:callCount("UpdateAsync")
		T.equal(a.core.save(USER, "Purchase"), false, "immediate save refused")
		T.equal(a.core.autosaveAll(), 0)
		T.equal(a.core.prepareTeleport(USER), false)
		T.equal(a.core.release(USER, "Leave"), true, "leave just drops the session")
		T.equal(world.store:callCount("UpdateAsync"), updatesBefore, "A never called the store again")
		T.equal(#a.kicks, 1, "no second kick")

		local record = H.stored(world, USER)
		T.equal(record.saveSeq, stolen.saveSeq, "B's record unchanged")
		T.equal(record.data.sim.coins, 50)
		T.equal(record.lockServer, "B")
	end)

	test("saveSeq: a record above what this server wrote is never overwritten", function()
		local world = H.world()
		local a = H.server(world, "A")
		a.core.load(USER)
		-- Something else wrote a newer state under A's lock name (should be impossible, but the
		-- write must still refuse instead of putting an older snapshot on top).
		local record = H.stored(world, USER)
		record.saveSeq = 40
		record.data.sim.coins = 4000
		world.store:SetAsync(H.key(USER), record)

		local ok, why = a.core.save(USER, "Autosave")
		T.equal(ok, false)
		T.equal(why, "Stale")
		T.equal(H.stored(world, USER).data.sim.coins, 4000)
		T.equal(#a.kicks, 1)
	end)
end)

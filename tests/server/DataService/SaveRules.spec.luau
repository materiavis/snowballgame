--!strict
-- Concept 6.5 / 12.1 loading, saving, teleport and crash rules against the fake store
-- (issue #26 AC1, AC2, AC11). Each test names the 6.5 row it covers.

local T = require("../../TestKit")
local H = require("./Harness")

local USER = H.USER
local Config = H.Config

-- Saves an existing profile with coins = 500 through a first server that then leaves.
local function seedProfile(world: H.World): any
	local first = H.server(world, "seed")
	first.core.load(USER)
	first.core.getData(USER).sim.coins = 500
	T.equal(first.core.release(USER, "Leave"), true, "seed release")
	return H.stored(world, USER)
end

return T.suite("DataService save rules (6.5)", function(test)
	test("12.1: a new player gets schema v1 defaults and the lock", function()
		local world = H.world()
		local server = H.server(world, "A")
		T.equal(server.core.load(USER), "Loaded")
		local data = server.core.getData(USER)
		T.equal(data.schemaVersion, 1)
		T.equal(data.sim.inventorySize, Config.InventorySize)
		local record = H.stored(world, USER)
		T.equal(record.lockServer, "A")
		T.equal(record.lockTime, world.clock.now())
		T.equal(record.saveSeq, 0)
	end)

	test("6.5 Laden: a load failure writes nothing, reports Failed and retries until it works", function()
		local world = H.world()
		local before = seedProfile(world)
		world.store:setFailing("UpdateAsync", true)

		local server = H.server(world, "B")
		local sawFailed = false
		server.onWait = function()
			if server.core.getStatus(USER) == "Failed" and not sawFailed then
				sawFailed = true
				T.equal(server.core.getData(USER), nil, "no profile handed out while failed")
				T.equal(H.stored(world, USER).data.sim.coins, 500, "saved data untouched")
				world.store:setFailing("UpdateAsync", false)
			end
		end
		T.equal(server.core.load(USER), "Loaded")
		T.isTrue(sawFailed, "status was Failed before the retry")
		T.equal(server.core.getData(USER).sim.coins, 500, "loaded the saved data, not defaults")
		T.equal(H.stored(world, USER).saveSeq, before.saveSeq, "loading does not bump saveSeq")
		T.isTrue(H.logged(server, "nothing written"), "failure logged")
	end)

	test("6.5 Laden: a player who leaves while loading fails never causes a write", function()
		local world = H.world()
		local before = seedProfile(world)
		world.store:setFailing("UpdateAsync", true)
		local server = H.server(world, "B")
		server.onWait = function()
			if server.core.getStatus(USER) == "Failed" then
				server.core.release(USER, "Leave")
			end
		end
		T.equal(server.core.load(USER), "Released")
		world.store:setFailing("UpdateAsync", false)
		local after = H.stored(world, USER)
		T.equal(after.saveSeq, before.saveSeq)
		T.equal(after.data.sim.coins, 500)
		T.equal(after.lockServer, nil, "no lock left behind")
	end)

	test("6.5 Laden: a record this server cannot read (newer schema) is never overwritten", function()
		local world = H.world()
		world.store:SetAsync(H.key(USER), { saveSeq = 7, data = { schemaVersion = 99, future = true } })
		local server = H.server(world, "A")
		server.onWait = function()
			server.core.release(USER, "Leave")
		end
		T.equal(server.core.load(USER), "Released")
		T.equal(H.statuses(server, USER)[2], "Failed")
		local record = H.stored(world, USER)
		T.equal(record.data.schemaVersion, 99)
		T.equal(record.data.future, true)
		T.equal(record.lockServer, nil)
	end)

	test("6.5 Sofort speichern: SaveNow is stored when it returns", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.getData(USER).sim.rebirths = 1
		T.equal(server.core.save(USER, "Rebirth"), true)
		local record = H.stored(world, USER)
		T.equal(record.data.sim.rebirths, 1)
		T.equal(record.saveSeq, 1)
		T.equal(record.lockServer, "A", "lock kept")
	end)

	test("6.5 Speichern schlägt fehl: retried, state kept on the server, older store not touched", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.getData(USER).sim.coins = 10
		server.core.save(USER, "Autosave")

		server.core.getData(USER).sim.coins = 20
		world.store:failNext("UpdateAsync", Config.StoreAttempts)
		local ok, why = server.core.save(USER, "Purchase")
		T.equal(ok, false)
		T.equal(why, "StoreError")
		T.equal(#server.waits, Config.StoreAttempts - 1, "backoff between attempts")
		T.equal(server.core.getData(USER).sim.coins, 20, "state kept in memory")
		T.equal(H.stored(world, USER).data.sim.coins, 10, "store still has the older save")

		T.equal(server.core.autosaveAll(), 1, "next autosave writes the kept state")
		T.equal(H.stored(world, USER).data.sim.coins, 20)
		T.equal(H.stored(world, USER).saveSeq, 2)
	end)

	test("6.5 Speichern schlägt fehl: a save that fails a few times still lands within its retries", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.getData(USER).sim.coins = 5
		world.store:failNext("UpdateAsync", Config.StoreAttempts - 1)
		T.equal(server.core.save(USER, "Purchase"), true)
		T.equal(H.stored(world, USER).data.sim.coins, 5)
	end)

	test("6.5 Teleport: save and release first; on failure the player stays with the lock", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.getData(USER).sim.lastZone = 3

		world.store:setFailing("UpdateAsync", true)
		local ok, why = server.core.prepareTeleport(USER)
		T.equal(ok, false)
		T.equal(why, "StoreError")
		T.equal(server.core.getStatus(USER), "Loaded", "player stays, still playable")
		T.equal(H.stored(world, USER).lockServer, "A", "lock not released")
		world.store:setFailing("UpdateAsync", false)

		T.equal(server.core.prepareTeleport(USER), true)
		local record = H.stored(world, USER)
		T.equal(record.lockServer, nil, "released for the destination")
		T.equal(record.data.sim.lastZone, 3)
		T.equal(server.core.getStatus(USER), "Teleported")
		T.equal(server.core.save(USER, "Autosave"), false, "no writes after the hand-off")
		local destination = H.server(world, "B")
		T.equal(destination.core.load(USER), "Loaded")
		T.equal(#destination.waits, 0, "destination did not wait for a lock")
	end)

	test("6.5 Teleport: a failed teleport takes the lock back unless another server loaded", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.prepareTeleport(USER)
		T.equal(server.core.resumeAfterTeleport(USER), true)
		T.equal(server.core.getStatus(USER), "Loaded")
		T.equal(H.stored(world, USER).lockServer, "A")

		server.core.prepareTeleport(USER)
		H.server(world, "B").core.load(USER)
		local ok, why = server.core.resumeAfterTeleport(USER)
		T.equal(ok, false)
		T.equal(why, "LockLost")
		T.equal(#server.kicks, 1)
	end)

	test("6.5 Serverabsturz: at most the autosave interval is lost, immediate saves never", function()
		T.equal(Config.AutosaveInterval, 120, "concept 12.1: every 2 minutes")
		local world = H.world()
		local crashed = H.server(world, "A")
		crashed.core.load(USER)
		local data = crashed.core.getData(USER)
		data.sim.rebirths = 1
		crashed.core.save(USER, "Rebirth")
		world.clock.advance(Config.AutosaveInterval)
		data.sim.coins = 300
		crashed.core.autosaveAll()
		data.sim.coins = 999 -- after the last autosave: lost in the crash
		-- Server A dies here: no release, no further autosave.

		local crashAt = world.clock.now()
		local next = H.server(world, "B")
		T.equal(next.core.load(USER), "Loaded")
		local loaded = next.core.getData(USER)
		T.equal(loaded.sim.rebirths, 1, "immediate save kept")
		T.equal(loaded.sim.coins, 300, "last autosave kept")
		local waited = world.clock.now() - crashAt
		T.isTrue(waited >= Config.LockTimeout - Config.AutosaveInterval, "waited out the fresh lock")
		T.isTrue(waited <= Config.LockTimeout + Config.LockRetryInterval, "took over soon after the timeout")
		T.isTrue(H.logged(next, "took over the stale lock of A"), "steal logged")
	end)

	test("6.5 Verlassen: ball size is not saved, collection finds are", function()
		local defaults = H.Schema.newProfile()
		for _, key in { "ballSize", "ball", "ballFinds" } do
			T.equal(defaults[key], nil, key)
			T.equal(defaults.sim[key], nil, `sim.{key}`)
		end
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.getData(USER).sim.collection.finds.IceCube = 1_000_000
		server.core.release(USER, "Leave")
		local again = H.server(world, "B")
		again.core.load(USER)
		T.equal(again.core.getData(USER).sim.collection.finds.IceCube, 1_000_000)
	end)

	test("12.1 Verlassen: a failed save on leave keeps the lock and autosave finishes it", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.getData(USER).sim.coins = 42
		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.release(USER, "Leave"), false)
		T.equal(H.stored(world, USER).lockServer, "A", "lock held, so no server loads older data")
		world.store:setFailing("UpdateAsync", false)
		T.equal(server.core.autosaveAll(), 1)
		local record = H.stored(world, USER)
		T.equal(record.lockServer, nil)
		T.equal(record.data.sim.coins, 42)
		T.equal(server.core.getStatus(USER), nil, "session gone")
	end)

	test("12.1 Verlassen: rejoining the same server before a failed release resumes the newest state", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		server.core.getData(USER).sim.coins = 77
		world.store:setFailing("UpdateAsync", true)
		server.core.release(USER, "Leave")
		T.equal(server.core.load(USER), "Loaded")
		T.equal(server.core.getData(USER).sim.coins, 77)
	end)

	test("12.1 BindToClose: every profile is saved and released, no new loads", function()
		local world = H.world()
		local server = H.server(world, "A")
		for userId = 1, 3 do
			server.core.load(userId)
			server.core.getData(userId).sim.coins = userId
		end
		server.core.close()
		for _, userId in server.core.userIds() do
			T.equal(server.core.release(userId, "Shutdown"), true)
		end
		for userId = 1, 3 do
			local record = H.stored(world, userId)
			T.equal(record.lockServer, nil)
			T.equal(record.data.sim.coins, userId)
		end
		T.equal(server.core.load(4), "Released", "no load after close")
		T.equal(H.stored(world, 4), nil)
	end)

	test("load hooks run before Loaded, and late hooks run for loaded profiles", function()
		local world = H.world()
		local server = H.server(world, "A")
		local seen: { string } = {}
		server.core.addLoadHook(function(userId, data)
			table.insert(seen, `{userId}:{server.core.getStatus(userId)}:{data.schemaVersion}`)
		end)
		server.core.load(USER)
		T.equal(seen[1], `{USER}:Loading:1`)
		local late = 0
		server.core.addLoadHook(function()
			late += 1
		end)
		T.equal(late, 1)
	end)
end)

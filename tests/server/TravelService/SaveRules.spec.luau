--!strict
-- Concept 6.5 travel edge cases against DataCore and the fake store (issue #28 AC2, AC7):
-- save before every teleport, a failed save or teleport keeps the player in place with a
-- message and an automatic retry, a failed teleport takes the lock back, a lock lost meanwhile
-- ends the session without retry, and a load failure outside the Lobby returns to the Lobby.

local T = require("../../TestKit")
local TH = require("./TravelHarness")
local H = require("../DataService/Harness")

local USER = TH.USER
local Config = TH.Config

local function live(role: any, worldIndex: number?, extra: any?): any
	local options: any = { role = role, worldIndex = worldIndex, places = TH.PUBLISHED }
	for key, value in extra or {} do
		options[key] = value
	end
	return TH.new(options)
end

return T.suite("TravelService save rules (6.5)", function(test)
	test("5.6: every teleport is preceded by a save that releases the lock", function()
		local h = live("Lobby")
		h.server.core.getData(USER).sim.coins = 77
		local seqBefore = TH.stored(h).saveSeq
		h.onTeleport = function()
			local record = TH.stored(h)
			T.equal(record.lockServer, nil, "lock released before the teleport")
			T.equal(record.saveSeq, seqBefore + 1, "saved before the teleport")
			T.equal(record.data.sim.coins, 77, "the newest state is stored")
		end
		T.equal(h.travel.travel(USER, "Portal"), "Done")
		T.equal(#h.calls, 1)
		T.equal(#h.notices, 0, "no message on success")
		T.isTrue(not h.travel.isBusy(USER))
	end)

	test("6.5 Speichern schlägt fehl (forced, DataFailSave): player stays, message, retry, lock kept", function()
		local h = live("Lobby", nil, { saveFault = true })
		local seqBefore = TH.stored(h).saveSeq
		T.equal(h.travel.travel(USER, "Portal"), "SaveFailed")
		T.equal(#h.calls, 0, "never teleported")
		local keys = TH.noticeKeys(h)
		T.equal(TH.count(keys, "SaveRetry"), Config.SaveAttempts - 1, "a retry message per automatic retry")
		T.equal(keys[#keys], "SaveFailed", "final message")
		T.isTrue(TH.count(h.waits, Config.SaveRetryDelay) >= Config.SaveAttempts - 1, "waited between attempts")
		local record = TH.stored(h)
		T.equal(record.lockServer, "A", "the lock is still held here")
		T.equal(record.saveSeq, seqBefore, "nothing written")
		T.equal(h.server.core.getStatus(USER), "Loaded", "the player keeps playing here")
		T.isTrue(not h.travel.isBusy(USER), "a later travel may start again")
		T.equal(#h.server.kicks, 0, "nobody is kicked")
	end)

	test("6.5: a save that works on the automatic retry continues to the teleport", function()
		local h = live("Lobby", nil, { saveFault = true })
		h.onWait = function(seconds)
			if seconds == Config.SaveRetryDelay then
				h.failSave = false
			end
		end
		T.equal(h.travel.travel(USER, "Portal"), "Done")
		T.equal(#h.calls, 1)
		T.equal(TH.noticeKeys(h)[1], "SaveRetry")
	end)

	test("6.5 Teleport schlägt fehl: the lock is taken back, message, and the retry works", function()
		local h = live("Simulator", 1)
		h.results = { "Failure: test" }
		local afterFirst: any = nil
		h.onTeleport = function(call)
			if call.info.attempt == 2 then
				afterFirst = { status = h.server.core.getStatus(USER), lock = TH.stored(h).lockServer }
			end
		end
		T.equal(h.travel.travel(USER, "LobbyButton"), "Done")
		T.equal(#h.calls, 2, "one automatic retry")
		T.equal(TH.noticeKeys(h)[1], "TeleportRetry")
		T.isTrue(afterFirst ~= nil, "second attempt ran")
		T.equal(h.waits[1], Config.TeleportRetryBase, "backoff before the retry")
		T.isTrue(H.logged(h.server, "loaded"), "session existed")
	end)

	test("6.5: a teleport that keeps failing ends with the player in place and their lock", function()
		local h = live("Arena")
		h.results = {}
		for _ = 1, Config.TeleportAttempts do
			table.insert(h.results, "Flooded: test")
		end
		T.equal(h.travel.travel(USER, "ToLobby"), "TeleportFailed")
		T.equal(#h.calls, Config.TeleportAttempts)
		local keys = TH.noticeKeys(h)
		T.equal(TH.count(keys, "TeleportRetry"), Config.TeleportAttempts - 1)
		T.equal(keys[#keys], "TeleportFailed")
		T.equal(h.server.core.getStatus(USER), "Loaded", "resumed after every failure")
		T.equal(TH.stored(h).lockServer, "A", "the lock is held here again")
		-- Each attempt saved first: one release write per attempt, each resumed.
		T.equal(TH.stored(h).saveSeq, Config.TeleportAttempts)
		T.isTrue(not h.travel.isBusy(USER))
	end)

	test("6.5: a lock lost while the teleport failed ends the session, no retry", function()
		local h = live("Lobby")
		h.results = { "Failure: test" }
		local other = H.server(h.world, "B")
		h.onTeleport = function()
			-- The player reached another server that loaded the released profile meanwhile.
			T.equal(other.core.load(USER), "Loaded")
		end
		T.equal(h.travel.travel(USER, "Portal"), "Lost")
		T.equal(#h.calls, 1, "no further teleport")
		T.equal(#h.server.kicks, 1, "DataService kicked the player")
		T.equal(h.server.core.getStatus(USER), "Lost")
		T.equal(TH.stored(h).lockServer, "B", "the other server keeps the profile")
		T.equal(TH.count(TH.noticeKeys(h), "TeleportRetry"), 0)
	end)

	test("6.5: a resume that keeps hitting store errors asks the player to rejoin, nothing lost", function()
		local h = live("Lobby")
		h.server.core.getData(USER).sim.coins = 9
		h.results = { "Failure: test" }
		h.onTeleport = function()
			h.failLoad = true -- resume is a "Load" purpose store call
		end
		T.equal(h.travel.travel(USER, "Portal"), "Lost")
		T.equal(#h.calls, 1)
		T.equal(h.kicks[1], Config.Messages.ResumeFailed)
		T.equal(TH.noticeKeys(h)[1], "ResumeFailed")
		local record = TH.stored(h)
		T.equal(record.lockServer, nil, "released, so the next server loads at once")
		T.equal(record.data.sim.coins, 9, "the state saved before the teleport is kept")
	end)

	test("GameFull on a friend's server switches to any server of that world", function()
		local h = live("Lobby")
		h.friends = { 55 }
		h.presence.publishServer("J1", 1, { 55 })
		h.results = { "GameFull: full" }
		T.equal(h.travel.travel(USER, "Portal"), "Done")
		T.equal(h.calls[1].target.server, "Friend")
		T.equal(h.calls[2].target.server, "Public")
	end)

	test("a second request while travelling is refused, and so is a profile that is not loaded", function()
		local h = live("Simulator", 1)
		local second: string? = nil
		h.onTeleport = function()
			second = h.travel.travel(USER, "LobbyButton")
		end
		T.equal(h.travel.travel(USER, "LobbyButton"), "Done")
		T.equal(second, "Refused")
		T.equal(#h.calls, 1)

		local fresh = live("Simulator", 1, { noLoad = true })
		T.equal(fresh.travel.travel(USER, "LobbyButton"), "Refused")
		T.equal(TH.noticeKeys(fresh)[1], "NotReady")
	end)

	test("live servers refuse unpublished destinations before saving", function()
		local h = TH.new({ role = "Simulator", worldIndex = 1 }) -- Config.Places: all 0
		local seqBefore = TH.stored(h).saveSeq
		T.equal(h.travel.travel(USER, "WorldGate"), "Refused")
		T.equal(#h.calls, 0)
		T.equal(TH.stored(h).saveSeq, seqBefore, "nothing saved")
		T.equal(TH.stored(h).lockServer, "A")
	end)

	test("ADR 0003 load failure outside the Lobby: retries, then back to the Lobby without a write", function()
		local h = live("Simulator", 1, { noLoad = true, loadFault = true })
		local seeded = H.server(h.world, "seed")
		seeded.core.load(USER)
		seeded.core.getData(USER).sim.coins = 500
		seeded.core.release(USER, "Leave")
		local before = TH.stored(h)

		local failed = 0
		h.server.core.subscribe(function(event)
			if event.kind == "Status" then
				if event.status == "Failed" then
					failed += 1
				end
				h.loadFail.onLoadStatus(event.userId, event.status)
			end
		end)
		T.equal(h.server.core.load(USER), "Released", "the player left for the Lobby")
		T.equal(failed, Config.LoadFailuresBeforeLobby, "returned after the configured failed loads")
		T.equal(#h.calls, 1)
		T.equal(h.calls[1].dest.role, "Lobby")
		T.equal(h.calls[1].info.intent, "LoadFailReturn")
		T.equal(TH.noticeKeys(h)[1], "LoadFailedReturn")
		T.isTrue(TH.count(h.waits, Config.LoadFailReturnDelay) >= 1, "message shown before leaving")
		local after = TH.stored(h)
		T.equal(after.saveSeq, before.saveSeq, "never written")
		T.equal(after.data.sim.coins, 500)
		T.equal(after.lockServer, nil)
	end)

	test("load failures in the Lobby never send anyone away", function()
		local h = live("Lobby", nil, { noLoad = true })
		for _ = 1, Config.LoadFailuresBeforeLobby + 2 do
			h.loadFail.onLoadStatus(USER, "Failed")
		end
		T.equal(#h.calls, 0)
		T.equal(#h.notices, 0)
	end)

	test("a load that recovers during the message delay keeps the player", function()
		local h = live("Arena", nil, { noLoad = true, loadFault = true })
		h.onWait = function(seconds)
			if seconds == Config.LoadFailReturnDelay then
				h.failLoad = false
				h.server.core.load(USER) -- the next DataService load attempt works
			end
		end
		for _ = 1, Config.LoadFailuresBeforeLobby do
			h.loadFail.onLoadStatus(USER, "Failed")
		end
		T.equal(#h.calls, 0, "no teleport once loaded")
		T.equal(h.server.core.getStatus(USER), "Loaded")
	end)
end)

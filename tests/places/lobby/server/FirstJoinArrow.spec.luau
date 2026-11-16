--!strict
-- The first-join arrow (issue #37 AC5, AC12; ADR 0015) on the schema v1 flag
-- tutorial.seenSingleArrow, against a real TravelCore + DataCore on the fake store: shown for a
-- new player, set and stored by the first portal travel (in the Teleport save, because a real
-- teleport releases the session there), never shown again after a rejoin, and back when the
-- travel did not happen (forced save failure, failed teleport).

local T = require("../../../TestKit")
local TH = require("../../../server/TravelService/TravelHarness")
local H = require("../../../server/DataService/Harness")
local FirstJoinArrow = require("../../../../src/places/lobby/server/PortalService/FirstJoinArrow")

local USER = TH.USER

-- What PortalService.travel does around TravelService.ToSimulator.
local function portalTravel(h: any): (string, boolean)
	local changed = FirstJoinArrow.markSeen(h.server.core.getData(USER))
	local outcome = h.travel.travel(USER, "Portal")
	local restored = FirstJoinArrow.afterTravel(h.server.core.getData(USER), changed, outcome)
	return outcome, restored
end

local function storedFlag(h: any): any
	return TH.stored(h).data.tutorial.seenSingleArrow
end

return T.suite("Lobby first-join arrow (7.1, 10.1, 6.5)", function(test)
	test("rules: shown only for a loaded profile that has not seen it", function()
		local profile = H.Schema.newProfile()
		T.equal(FirstJoinArrow.shouldShow(profile), true, "new player")
		T.equal(FirstJoinArrow.shouldShow(nil), false, "not loaded: nothing shown")
		T.equal(FirstJoinArrow.shouldShow({}), false, "no tutorial table")
		T.equal(FirstJoinArrow.markSeen(profile), true)
		T.equal(FirstJoinArrow.shouldShow(profile), false)
		T.equal(FirstJoinArrow.markSeen(profile), false, "second travel changes nothing")
		T.equal(FirstJoinArrow.afterTravel(profile, false, "SaveFailed"), false, "not ours to undo")
		T.equal(profile.tutorial.seenSingleArrow, true)
		T.equal(FirstJoinArrow.reset(profile), true)
		T.equal(FirstJoinArrow.shouldShow(profile), true)
	end)

	test("AC5: the first portal travel (Studio stub) sets the flag and stores it in the Teleport save", function()
		local h = TH.new({ role = "Lobby", stub = true })
		T.equal(FirstJoinArrow.shouldShow(h.server.core.getData(USER)), true, "new player sees the arrow")
		T.equal(storedFlag(h), false)
		local outcome, restored = portalTravel(h)
		T.equal(outcome, "Done")
		T.equal(restored, false)
		T.equal(storedFlag(h), true, "stored by the save before the teleport")
		T.equal(FirstJoinArrow.shouldShow(h.server.core.getData(USER)), false, "resumed session: no arrow")
	end)

	test("AC5/AC12: after the first travel and a rejoin the arrow never appears again", function()
		local h = TH.new({ role = "Lobby", stub = true })
		portalTravel(h)
		T.equal(h.server.core.release(USER, "Leave"), true)
		local next = H.server(h.world, "B")
		next.core.load(USER)
		T.equal(FirstJoinArrow.shouldShow(next.core.getData(USER)), false, "rejoin on another server")
	end)

	test("AC5: a real teleport (the player leaves) stores the flag for the destination", function()
		local h = TH.new({ role = "Lobby", places = TH.PUBLISHED })
		local outcome = portalTravel(h)
		T.equal(outcome, "Done")
		T.equal(storedFlag(h), true)
		T.equal(TH.stored(h).lockServer, nil, "released for the Simulator")
	end)

	test("AC12 forced save failure (DataFailSave): no travel, the arrow comes back, nothing wrong stored", function()
		local h = TH.new({ role = "Lobby", stub = true, saveFault = true })
		local outcome, restored = portalTravel(h)
		T.equal(outcome, "SaveFailed")
		T.equal(restored, true)
		T.equal(FirstJoinArrow.shouldShow(h.server.core.getData(USER)), true, "still a new player")
		T.equal(storedFlag(h), false)
		h.failSave = false
		T.equal(h.server.core.release(USER, "Leave"), true)
		local next = H.server(h.world, "B")
		next.core.load(USER)
		T.equal(FirstJoinArrow.shouldShow(next.core.getData(USER)), true, "rejoin: arrow still shown")
	end)

	test("a teleport that fails every attempt restores the arrow and keeps the session", function()
		local h = TH.new({ role = "Lobby", stub = true })
		h.stubFailures = 99
		local outcome, restored = portalTravel(h)
		T.equal(outcome, "TeleportFailed")
		T.equal(restored, true)
		T.equal(h.server.core.getStatus(USER), "Loaded")
		T.equal(FirstJoinArrow.shouldShow(h.server.core.getData(USER)), true)
		-- The next save writes the restored value over the one the Teleport saves stored.
		T.equal(h.server.core.save(USER, "Autosave"), true)
		T.equal(storedFlag(h), false)
	end)

	test("a refused travel (profile not loaded) changes nothing", function()
		local h = TH.new({ role = "Lobby", stub = true, noLoad = true })
		local outcome, restored = portalTravel(h)
		T.equal(outcome, "Refused")
		T.equal(restored, false, "there was no profile to change")
	end)
end)

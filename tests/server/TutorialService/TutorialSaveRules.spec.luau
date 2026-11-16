--!strict
-- The tutorial state against DataService and the fake store (#42 AC4, AC9): the concept 6.5
-- rows that apply. TutorialCore works on DataCore.getData(...).tutorial, exactly as
-- TutorialService does through DataService.GetProfile. No save-format change: schema v1 fields.

local T = require("../../TestKit")
local H = require("../DataService/Harness")
local TutorialConfig = require("../../../src/shared/Config/Tutorial")
local TutorialCore = require("../../../src/server/Services/TutorialService/TutorialCore")

local USER = H.USER
local core = TutorialCore.new(TutorialConfig :: any)

local function tutorialOn(server: H.Server): any
	local profile = server.core.getData(USER)
	return profile and profile.tutorial
end

local function storedTutorial(world: H.World): any
	local record = H.stored(world, USER)
	return record and record.data.tutorial
end

local function activeOn(server: H.Server, place: string, eligible: { [string]: boolean }): { string }
	local _, active = core.select(place, tutorialOn(server), eligible, {})
	return active
end

return T.suite("TutorialService save rules (6.5)", function(test)
	test("AC4: a new profile has every hint unseen in the schema v1 fields", function()
		local profile = H.Schema.newProfile()
		T.equal(profile.tutorial.seenMultiArrow, false)
		T.equal(next(profile.tutorial.hints), nil)
		T.equal(#core.doneList(profile.tutorial), 0)
	end)

	test("AC4: done hints are stored with the next save and survive a rejoin on another server", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		T.isTrue(core.markDone(tutorialOn(server), "LobbyMove"))
		T.isTrue(core.markDone(tutorialOn(server), "LobbyMultiArrow"))
		server.core.autosaveAll()
		local stored = storedTutorial(world)
		T.equal(stored.hints.LobbyMove, true)
		T.equal(stored.seenMultiArrow, true)
		T.equal(server.core.release(USER, "Leave"), true)

		local other = H.server(world, "B")
		other.core.load(USER)
		T.equal(table.concat(core.doneList(tutorialOn(other)), ","), "LobbyMove,LobbyMultiArrow")
		T.equal(#activeOn(other, "Lobby", { LobbyMove = true, LobbyMultiArrow = true }), 0, "never shown again")
	end)

	test(
		"AC9 6.5 Speichern: a seen hint stays seen after a failed save and a rejoin, and lands with the next save",
		function()
			local world = H.world()
			local server = H.server(world, "A")
			server.core.load(USER)
			server.core.autosaveAll()

			world.store:setFailing("UpdateAsync", true)
			T.isTrue(core.markDone(tutorialOn(server), "ZoneMove"))
			T.equal(server.core.save(USER, "Autosave"), false, "forced save failure")
			T.equal(storedTutorial(world).hints.ZoneMove, nil, "the store still has the old record")
			T.equal(core.isDone(tutorialOn(server), "ZoneMove"), true, "the server keeps it")

			-- DataSimulateRejoin while saves still fail: the release keeps the session, the reload
			-- resumes it, and the hint is still seen.
			T.equal((server.core.release(USER, "Leave")), false)
			T.equal(server.core.load(USER), "Loaded")
			T.equal(core.isDone(tutorialOn(server), "ZoneMove"), true)
			T.equal(#activeOn(server, "Simulator", { ZoneMove = true }), 0, "the controls hint does not come back")

			world.store:setFailing("UpdateAsync", false)
			T.equal(server.core.save(USER, "Retry"), true)
			T.equal(storedTutorial(world).hints.ZoneMove, true, "the next save stores it")
			T.equal(server.core.release(USER, "Leave"), true)
			local other = H.server(world, "B")
			other.core.load(USER)
			T.equal(core.isDone(tutorialOn(other), "ZoneMove"), true)
		end
	)

	test("AC9 6.5 Laden: a failed load shows nothing and never resets the stored hints", function()
		local world = H.world()
		local server = H.server(world, "A")
		server.core.load(USER)
		core.markDone(tutorialOn(server), "ZoneMove")
		core.markDone(tutorialOn(server), "MaxScale")
		T.equal(server.core.release(USER, "Leave"), true)

		local failing = true
		local other = H.server(world, "B", function(purpose)
			return purpose == "Load" and failing
		end)
		-- load() retries every LoadRetryInterval; the checks run in that wait, while it is Failed,
		-- then the store "recovers" (DataFailLoad = false in Studio).
		local whileFailed: { any }? = nil
		other.onWait = function()
			if whileFailed == nil and other.core.getStatus(USER) == "Failed" then
				whileFailed = {
					profile = tutorialOn(other),
					active = #activeOn(other, "Simulator", { ZoneMove = true, MaxScale = true }),
					marked = core.markDone(tutorialOn(other), "UpgradesButton"),
					stored = storedTutorial(world).hints.ZoneMove,
				}
				failing = false
			end
		end
		T.equal(other.core.load(USER), "Loaded")
		local seen = whileFailed :: any
		T.isTrue(seen ~= nil, "the load failed first")
		T.equal(seen.profile, nil, "no profile while the load failed")
		T.equal(seen.active, 0, "no hint, not as new")
		T.equal(seen.marked, false, "nothing to write into")
		T.equal(seen.stored, true, "the stored record is untouched")
		T.equal(table.concat(core.doneList(tutorialOn(other)), ","), "ZoneMove,MaxScale")
		T.equal(table.concat(activeOn(other, "Simulator", { UpgradesButton = true }), ","), "UpgradesButton")
	end)
end)

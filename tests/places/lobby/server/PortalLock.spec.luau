--!strict
-- Regression for #37 round 1, R1 (AC7, concept 6.5): while a rejoin's load is still running
-- (DataLoadStatus "Loading", then "Failed" with DataFailLoad) the portal is locked, no travel
-- starts and nothing is saved. Runs the Studio rejoin (release, then load) on a real DataCore
-- and TravelCore with the fake store and tries the portal at every wait of the failing load.

local T = require("../../../TestKit")
local TH = require("../../../server/TravelService/TravelHarness")
local SourceSection = require("../../../helpers/SourceSection")
local LobbyConfig = require("../../../../src/shared/Config/Lobby")
local PortalCore = require("../../../../src/places/lobby/server/PortalService/PortalCore")

local USER = TH.USER
local PORTAL_SERVICE = "src/places/lobby/server/PortalService/init.luau"

return T.suite("Lobby portal lock while the profile is not loaded (6.5, #37 R1)", function(test)
	test("the gate is open only for Loaded", function()
		T.equal(PortalCore.isOpenFor("Loaded"), true)
		for _, status in { "Loading", "Failed", "Teleported", "Lost", "Released", nil, "", 1 } do
			T.equal(PortalCore.isOpenFor(status), false, tostring(status))
		end
	end)

	test("rejoin with DataFailLoad: locked during Loading and Failed, no countdown, no travel, no save", function()
		local h = TH.new({ role = "Lobby", stub = true })
		local portal = PortalCore.new({
			countdown = LobbyConfig.PortalCountdown,
			closedModes = LobbyConfig.ClosedPortalModes,
			now = h.world.clock.now,
		})
		local seqBefore = TH.stored(h).saveSeq
		-- Studio DataSimulateRejoin: release (saves), then load again with the load fault on.
		T.equal(h.server.core.release(USER, "StudioRejoin"), true)
		local seqAfterRelease = TH.stored(h).saveSeq
		T.equal(seqAfterRelease, seqBefore + 1, "the release saved once")
		h.failLoad = true

		local seen: { [string]: boolean } = {}
		local tries = 0
		-- DataCore's waits (the load retries) run this hook.
		h.server.onWait = function()
			if tries >= 12 then
				h.failLoad = false -- let the load work in the end
				return
			end
			tries += 1
			local status = h.server.core.getStatus(USER)
			seen[status] = true
			-- The character stands in the Singleplayer portal the whole time.
			local result = portal.step(USER, {
				inside = "Singleplayer",
				locked = not PortalCore.isOpenFor(status),
				travelling = h.travel.isBusy(USER),
			})
			T.equal(result.state, "Locked", `portal state while {status}`)
			T.equal(result.travel, false)
			T.equal(portal.remaining(USER), 0, "no countdown")
			-- Even a travel started another way is refused and saves nothing.
			T.equal(h.travel.travel(USER, "Portal"), "Refused", `travel while {status}`)
			T.equal(select(1, h.server.core.prepareTeleport(USER)), false, `PrepareTeleport while {status}`)
		end
		T.equal(h.server.core.load(USER), "Loaded")

		T.isTrue(seen.Loading, "the Loading window was tried")
		T.isTrue(seen.Failed, "the Failed window was tried")
		T.equal(#h.calls, 0, "no teleport")
		T.equal(TH.stored(h).saveSeq, seqAfterRelease, "no save for the unloaded profile")
		local refused = 0
		for _, event in h.events do
			if event.state == "Refused" and event.detail == "NotLoaded" then
				refused += 1
			end
		end
		T.equal(refused, tries, "every try refused as NotLoaded")

		-- Loaded again while standing inside: the countdown starts now.
		local open = portal.step(USER, { inside = "Singleplayer", locked = false, travelling = false })
		T.equal(open.state, "Countdown")
	end)

	test("PortalService gates entry, every step and the travel thread on Loaded", function()
		local check =
			SourceSection.between(PORTAL_SERVICE, "local function checkPlayer", "local function onPlayerAdded")
		T.isTrue(SourceSection.at(check, "DataService.IsPortalLocked(player)") ~= nil)
		T.isTrue(SourceSection.at(check, "PortalCore.isOpenFor(DataService.GetLoadStatus(player))") ~= nil)
		local travel = SourceSection.between(PORTAL_SERVICE, "local function travel", "local function insideMode")
		local gate = SourceSection.at(travel, "PortalCore.isOpenFor(DataService.GetLoadStatus(player))")
		local run = SourceSection.at(travel, "pcall(run, player)")
		T.isTrue(gate ~= nil and run ~= nil and gate < run, "re-checked right before the travel")
	end)
end)

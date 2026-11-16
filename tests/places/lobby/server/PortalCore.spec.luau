--!strict
-- Portal state per player (issue #37 AC2, AC3, AC7; ADR 0015): the Singleplayer countdown of
-- Config.Lobby.PortalCountdown, walking out cancels, the closed Multiplayer portal starts
-- nothing, a locked profile or another travel starts nothing, and after a travel the character
-- has to walk out before the next countdown.

local T = require("../../../TestKit")
local FakeClock = require("../../../helpers/FakeClock")
local LobbyConfig = require("../../../../src/shared/Config/Lobby")
local PortalCore = require("../../../../src/places/lobby/server/PortalService/PortalCore")

local USER = 7

local function setUp()
	local clock = FakeClock.new(100)
	local core = PortalCore.new({
		countdown = LobbyConfig.PortalCountdown,
		closedModes = LobbyConfig.ClosedPortalModes,
		now = clock.now,
	})
	local function step(inside: string?, locked: boolean?, travelling: boolean?)
		return core.step(USER, { inside = inside, locked = locked == true, travelling = travelling == true })
	end
	-- Steps every PortalCheckInterval for `seconds` with the same input; returns the step that
	-- started a travel (if any) and how many steps travelled.
	local function hold(seconds: number, inside: string?, locked: boolean?): (any, number)
		local started: any = nil
		local travels = 0
		local steps = math.floor(seconds / LobbyConfig.PortalCheckInterval + 0.5)
		for _ = 1, steps do
			clock.advance(LobbyConfig.PortalCheckInterval)
			local result = step(inside, locked)
			if result.travel then
				travels += 1
				started = started or { at = clock.now(), result = result }
			end
		end
		return started, travels
	end
	return clock, core, step, hold
end

return T.suite("Lobby PortalCore (7.1, 6.5)", function(test)
	test("Vertical Slice values: 3 s countdown, Multiplayer closed, Singleplayer open", function()
		T.equal(LobbyConfig.PortalCountdown, 3)
		T.equal(LobbyConfig.ClosedPortalModes.Multiplayer, true)
		T.equal(LobbyConfig.ClosedPortalModes.Singleplayer, nil)
		T.isTrue(LobbyConfig.PortalCheckInterval > 0 and LobbyConfig.PortalCheckInterval <= 0.25)
	end)

	test("AC2: walking into the Singleplayer portal travels after 3 s, exactly once", function()
		local clock, core, step, hold = setUp()
		local first = step("Singleplayer")
		T.equal(first.state, "Countdown")
		T.equal(first.event, "Started")
		T.equal(first.endsAt, clock.now() + 3)
		T.near(core.remaining(USER), 3, 1e-9)
		local started, travels = hold(2.9, "Singleplayer")
		T.equal(started, nil, "not before 3 s")
		T.near(core.remaining(USER), 0.1, 1e-6)
		started, travels = hold(0.2, "Singleplayer")
		T.isTrue(started ~= nil, "travels at 3 s")
		T.equal(travels, 1, "one travel")
		T.equal(started.result.mode, "Singleplayer")
		T.equal(started.result.state, "Travelling")
		local _, more = hold(5, "Singleplayer")
		T.equal(more, 0, "no second travel while the first runs")
	end)

	test("AC2: walking out cancels; walking back in starts a new full countdown", function()
		local clock, core, step, hold = setUp()
		step("Singleplayer")
		hold(2.5, "Singleplayer")
		local out = step(nil)
		T.equal(out.state, "Idle")
		T.equal(out.event, "Cancelled")
		T.equal(out.endsAt, 0)
		T.equal(core.remaining(USER), 0)
		local back = step("Singleplayer")
		T.equal(back.endsAt, clock.now() + 3, "a fresh 3 s")
		local started = hold(2.9, "Singleplayer")
		T.equal(started, nil, "the 2.5 s before do not count")
	end)

	test("AC3: the Multiplayer portal is closed: no countdown, no travel", function()
		local _, core, step, hold = setUp()
		local inside = step("Multiplayer")
		T.equal(inside.state, "Closed")
		T.equal(inside.event, "Closed")
		T.equal(inside.endsAt, 0)
		local started, travels = hold(30, "Multiplayer")
		T.equal(started, nil)
		T.equal(travels, 0)
		T.equal(core.remaining(USER), 0)
		T.equal(step(nil).event, nil, "leaving a closed portal cancels nothing")
	end)

	test("AC7: a locked profile starts no countdown; unlocking while inside starts it", function()
		local _, _, step, hold = setUp()
		local locked = step("Singleplayer", true)
		T.equal(locked.state, "Locked")
		T.equal(locked.event, "Locked")
		local started, travels = hold(30, "Singleplayer", true)
		T.equal(started, nil, "locked for as long as the load fails")
		T.equal(travels, 0)
		local unlocked = step("Singleplayer", false)
		T.equal(unlocked.state, "Countdown")
		T.equal(unlocked.event, "Started")
		started = hold(3.1, "Singleplayer", false)
		T.isTrue(started ~= nil, "travels once loaded")
	end)

	test("AC7: the profile locking during the countdown cancels it", function()
		local _, _, step, hold = setUp()
		step("Singleplayer")
		hold(2, "Singleplayer")
		local locked = step("Singleplayer", true)
		T.equal(locked.state, "Locked")
		T.equal(locked.event, "CancelledLocked")
		local started = hold(5, "Singleplayer", true)
		T.equal(started, nil)
	end)

	test("another travel running (Busy) starts nothing", function()
		local _, _, step = setUp()
		local busy = step("Singleplayer", false, true)
		T.equal(busy.state, "Busy")
		T.equal(busy.travel, false)
	end)

	test("after a travel the character must leave before the next countdown", function()
		local _, core, step, hold = setUp()
		step("Singleplayer")
		hold(3.1, "Singleplayer")
		local finished = core.travelFinished(USER)
		T.equal(finished.state, "WaitExit")
		local started, travels = hold(10, "Singleplayer")
		T.equal(started, nil, "standing in the portal after a stub success does not loop")
		T.equal(travels, 0)
		T.equal(step(nil).state, "Idle")
		T.equal(step("Singleplayer").state, "Countdown", "walking in again counts down again")
	end)

	test("changed is true only when something the client shows changed", function()
		local _, _, step = setUp()
		T.equal(step(nil).changed, false, "Idle to Idle")
		T.equal(step("Singleplayer").changed, true)
		T.equal(step("Singleplayer").changed, false, "same countdown")
		T.equal(step("Singleplayer").event, nil)
	end)

	test("players are independent and forget resets one", function()
		local clock = FakeClock.new(0)
		local core = PortalCore.new({
			countdown = 3,
			closedModes = LobbyConfig.ClosedPortalModes,
			now = clock.now,
		})
		core.step(1, { inside = "Singleplayer", locked = false, travelling = false })
		core.step(2, { inside = "Multiplayer", locked = false, travelling = false })
		T.equal((core.get(1)), "Countdown")
		T.equal((core.get(2)), "Closed")
		core.forget(1)
		T.equal((core.get(1)), "Idle")
	end)
end)

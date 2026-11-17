--!strict
-- Player counts above the portals (issue #37 AC4; ADR 0015): read from PresenceStore's mode
-- entries (the fake MemoryStore), written as PlayerCount / PlayerCountAt on every portal of the
-- mode, refreshed at least every 30 s, a failed read keeps the last value.

local T = require("../../../TestKit")
local FakeClock = require("../../../helpers/FakeClock")
local FakePlayer = require("../../../helpers/FakePlayer")
local FakeMemoryStore = require("../../../../src/server/Services/PresenceStore/FakeMemoryStore")
local PresenceCore = require("../../../../src/server/Services/PresenceStore/PresenceCore")
local LobbyConfig = require("../../../../src/shared/Config/Lobby")
local MapConfig = require("../../../../src/shared/Config/Map")
local TravelConfig = require("../../../../src/shared/Config/Travel")
local PlayerCounts = require("../../../../src/places/lobby/server/PortalService/PlayerCounts")

local function setUp()
	local clock = FakeClock.new(1_000_000)
	local map = FakeMemoryStore.newMap(clock.now)
	local presence = PresenceCore.new({
		map = map,
		wait = clock.advance,
		log = function() end,
		now = clock.now,
		config = TravelConfig,
	})
	-- FakePlayer stands in for a portal Model: only SetAttribute/GetAttribute are used.
	local portals = {
		Singleplayer = { FakePlayer.new(1), FakePlayer.new(2) },
		Multiplayer = { FakePlayer.new(3) },
	}
	local waits: { number } = {}
	local counts = PlayerCounts.new({
		modes = MapConfig.PortalModes,
		refresh = LobbyConfig.PortalPlayerCountRefresh,
		getCount = presence.getModeCount,
		portalsOf = function(mode: string): any
			return portals[mode]
		end,
		countAttribute = MapConfig.PlayerCountAttribute,
		atAttribute = MapConfig.PlayerCountAtAttribute,
		now = clock.now,
		wait = function(seconds: number)
			table.insert(waits, seconds)
			clock.advance(seconds)
			if #waits >= 3 then
				error("stop")
			end
		end,
		log = function() end,
	})
	return clock, map, presence, portals, counts, waits
end

local function count(portal: any): any
	return portal:GetAttribute(MapConfig.PlayerCountAttribute)
end

return T.suite("Lobby portal player counts (7.1)", function(test)
	test("AC4: refreshed at least every 30 s", function()
		T.isTrue(LobbyConfig.PortalPlayerCountRefresh <= 30)
		T.isTrue(TravelConfig.PresenceRefresh <= 30, "Simulator servers publish at least every 30 s")
		local clock, _, presence, portals, counts, waits = setUp()
		presence.setModeCount("Singleplayer", "sim-1", 4)
		T.equal((pcall(counts.run)), false, "the loop runs until the test stops it")
		T.equal(#waits, 3)
		for _, seconds in waits do
			T.isTrue(seconds <= LobbyConfig.PortalPlayerCountRefresh, `waited {seconds}`)
		end
		T.equal(counts.lastRefresh(), clock.now() - waits[#waits], "refreshed right before each wait")
		-- sim-1 published once and never again, so after three refreshes (90 s) it has expired.
		T.equal(count(portals.Singleplayer[1]), 0)
	end)

	test("AC4: Singleplayer = players on all fresh Simulator servers; every portal of the mode shows it", function()
		local clock, _, presence, portals, counts = setUp()
		presence.setModeCount("Singleplayer", "sim-1", 4)
		presence.setModeCount("Singleplayer", "sim-2", 7)
		counts.refreshNow()
		T.equal(count(portals.Singleplayer[1]), 11)
		T.equal(count(portals.Singleplayer[2]), 11)
		T.equal(count(portals.Multiplayer[1]), 0, "nothing publishes Multiplayer yet")
		T.equal(portals.Singleplayer[1]:GetAttribute(MapConfig.PlayerCountAtAttribute), clock.now())

		presence.setModeCount("Singleplayer", "sim-1", 9)
		clock.advance(LobbyConfig.PortalPlayerCountRefresh)
		counts.refreshNow()
		T.equal(count(portals.Singleplayer[1]), 16, "the next refresh shows the change")
	end)

	test("a server that stopped refreshing drops out after the presence TTL", function()
		local clock, _, presence, portals, counts = setUp()
		presence.setModeCount("Singleplayer", "sim-1", 4)
		clock.advance(TravelConfig.PresenceTtl / 2)
		presence.setModeCount("Singleplayer", "sim-2", 3)
		clock.advance(TravelConfig.PresenceTtl / 2)
		counts.refreshNow()
		T.equal(count(portals.Singleplayer[1]), 3, "sim-1 is stale")
		presence.removeModeServer("Singleplayer", "sim-2")
		counts.refreshNow()
		T.equal(count(portals.Singleplayer[1]), 0)
	end)

	test("a failed read keeps the last count and its time", function()
		local clock, map, presence, portals, counts = setUp()
		presence.setModeCount("Singleplayer", "sim-1", 5)
		counts.refreshNow()
		local at = portals.Singleplayer[1]:GetAttribute(MapConfig.PlayerCountAtAttribute)
		map:setFailing(true)
		clock.advance(30)
		counts.refreshNow()
		T.equal(count(portals.Singleplayer[1]), 5)
		T.equal(
			portals.Singleplayer[1]:GetAttribute(MapConfig.PlayerCountAtAttribute),
			at,
			"the diagnostic shows it is stale"
		)
	end)

	test("a portal that binds later gets the last count at once", function()
		local _, _, presence, _, counts = setUp()
		presence.setModeCount("Singleplayer", "sim-1", 2)
		counts.refreshNow()
		local late = FakePlayer.new(9)
		counts.apply(late :: any, "Singleplayer")
		T.equal(count(late), 2)
	end)
end)

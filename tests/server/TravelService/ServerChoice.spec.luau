--!strict
-- Simulator server selection (concept 5.6, 6.5) and reserved servers for matches and private
-- contexts (ADR 0003, ADR 0010), against PresenceCore on the fake MemoryStore.

local T = require("../../TestKit")
local TH = require("./TravelHarness")
local LobbyConfig = require("../../../src/shared/Config/Lobby")

local USER = TH.USER
local Config = TH.Config
local SIM = { role = "Simulator", world = 1, zone = 1, placeId = 201, group = false }

local function harness(): any
	return TH.new({ role = "Lobby", places = TH.PUBLISHED })
end

return T.suite("TravelService server choice", function(test)
	test("no friend online: public, Roblox picks a server with a free place or opens one", function()
		local h = harness()
		local target = h.choice.choose(USER, SIM, nil) :: any
		T.equal(target.server, "Public")
		T.equal(target.jobId, nil)
	end)

	test("5.6: a friend in that world with a free place is preferred", function()
		local h = harness()
		h.friends = { 41, 42 }
		h.presence.publishServer("J-full", 1, table.create(LobbyConfig.SimulatorPlayers, 41))
		h.presence.setUser(41, 1, "J-full") -- friend 41 is on a full server
		h.presence.publishServer("J-free", 1, { 42 })
		local target = h.choice.choose(USER, SIM, nil) :: any
		T.equal(target.server, "Friend")
		T.equal(target.jobId, "J-free", "the full server is skipped")
		T.equal(target.friendId, 42)
	end)

	test("6.5: friends only on full servers or other worlds: public", function()
		local h = harness()
		h.friends = { 41, 43 }
		h.presence.publishServer("J-full", 1, table.create(LobbyConfig.SimulatorPlayers, 41))
		h.presence.setUser(41, 1, "J-full")
		h.presence.publishServer("J-w2", 2, { 43 })
		T.equal((h.choice.choose(USER, SIM, nil) :: any).server, "Public")
	end)

	test("stale presence is never used", function()
		local h = harness()
		h.friends = { 42 }
		h.presence.publishServer("J-free", 1, { 42 })
		h.world.clock.advance(Config.PresenceTtl)
		T.equal((h.choice.choose(USER, SIM, nil) :: any).server, "Public")
	end)

	test("a broken friend lookup or presence outage only loses the preference", function()
		local h = harness()
		h.friends = nil :: any -- friendsOf returns nil
		T.equal((h.choice.choose(USER, SIM, nil) :: any).server, "Public")
		h.friends = { 42 }
		h.presence.publishServer("J-free", 1, { 42 })
		h.presenceMap:setFailing(true)
		T.equal((h.choice.choose(USER, SIM, nil) :: any).server, "Public")
		T.isTrue(TH.logged(h.logs, "failed"), "outage logged")
	end)

	test("Arena: the match server from matchmaking, else one new reserved server", function()
		local h = harness()
		local arena = { role = "Arena", placeId = 300, group = true }
		local given = h.choice.choose(USER, arena, { accessCode = "match-7" }) :: any
		T.equal(given.server, "Reserved")
		T.equal(given.accessCode, "match-7")
		T.equal(given.reservedNew, false)
		T.equal(h.reserves, 0)
		local fresh = h.choice.choose(USER, arena, nil) :: any
		T.equal(fresh.accessCode, "code-1")
		T.equal(fresh.reservedNew, true)
	end)

	test("private context: one reserved Simulator server per world, found again by both sides", function()
		local h = harness()
		h.privateKey = "vip-1"
		h.friends = { 42 }
		h.presence.publishServer("J-free", 1, { 42 })
		local first = h.choice.choose(USER, SIM, nil) :: any
		T.equal(first.server, "Reserved", "private players never go to public servers")
		T.equal(first.reservedNew, true)
		T.equal(first.privateKey, "vip-1")
		local again = h.choice.choose(USER, SIM, nil) :: any
		T.equal(again.accessCode, first.accessCode, "same reserved server next time")
		T.equal(again.reservedNew, false)
		T.equal(h.reserves, 1)
		T.equal(h.presence.getPrivateKey("psid-1"), "vip-1", "the reserved server knows its context")
		local world2 = h.choice.choose(USER, { role = "Simulator", world = 2, zone = 11, placeId = 202 }, nil) :: any
		T.equal(world2.accessCode, "code-2", "another world gets its own server")
	end)

	test("Group travel shares one reserved server", function()
		local h = TH.new({ role = "Lobby", places = TH.PUBLISHED, users = { 1, 2 } })
		T.equal(h.travel.travelGroup({ 1, 2 }, "MatchStart", nil), "Started")
		T.equal(#h.calls, 2)
		T.equal(h.reserves, 1, "reserved once")
		T.equal(h.calls[1].target.accessCode, h.calls[2].target.accessCode)
		T.equal(h.calls[1].dest.role, "Arena")
	end)
end)

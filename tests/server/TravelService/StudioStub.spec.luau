--!strict
-- The Studio stub at PlaceId 0 (issue #28 AC1, ADR 0003 "Teleports in Studio"): one log line
-- per attempt with intent, origin, destination, server choice, zone and players, a simulated
-- failure path, and the player resumed afterwards so the next intent can be tested.

local T = require("../../TestKit")
local TH = require("./TravelHarness")
local ZonesConfig = require("../../../src/shared/Config/Zones")

local USER = TH.USER

local function stub(role: any, worldIndex: number?, users: { number }?): any
	return TH.new({ role = role, worldIndex = worldIndex, stub = true, users = users })
end

local function lastLine(h: any): string
	for index = #h.printed, 1, -1 do
		if string.find(h.printed[index], "STUB teleport", 1, true) then
			return h.printed[index]
		end
	end
	return ""
end

local function has(line: string, needle: string)
	T.isTrue(string.find(line, needle, 1, true) ~= nil, `"{needle}" in: {line}`)
end

return T.suite("TravelService Studio stub", function(test)
	test("AC1 Portal: Lobby -> last visited world and zone, placeholder PlaceId", function()
		local h = stub("Lobby")
		local sim = h.server.core.getData(USER).sim
		sim.lastWorld, sim.lastZone = 1, 4
		T.equal(h.travel.travel(USER, "Portal"), "Done")
		local line = lastLine(h)
		for _, needle in { "intent=Portal", "from=Lobby", "to=Simulator world=1 zone=4", "placeId=0" } do
			has(line, needle)
		end
		has(line, "server=Public")
		has(line, `players=P{USER}({USER})`)
		has(line, "-> ok")
	end)

	test("AC1 World gate: World 1 -> World 2, first zone", function()
		local h = stub("Simulator", 1)
		T.equal(h.travel.travel(USER, "WorldGate"), "Done")
		local line = lastLine(h)
		has(line, "intent=WorldGate")
		has(line, "from=Simulator")
		has(line, `to=Simulator world=2 zone={ZonesConfig.ZonesPerWorld + 1}`)
	end)

	test("AC1 Match start: Lobby -> Arena on one new reserved server for the group", function()
		local h = stub("Lobby", nil, { 1, 2 })
		T.equal(h.travel.travelGroup({ 1, 2 }, "MatchStart", nil), "Started")
		T.equal(#h.calls, 2)
		local line = lastLine(h)
		has(line, "intent=MatchStart")
		has(line, "to=Arena")
		has(line, "server=Reserved(new, code=studio-reserved-1)")
		has(line, "players=P1(1),P2(2)")
		T.isTrue(TH.logged(h.printed, "STUB ReserveServer"), "reserve logged")
	end)

	test("AC1 Replay and To Lobby from the Arena", function()
		local h = stub("Arena", nil, { 1, 2 })
		T.equal(h.travel.travelGroup({ 1, 2 }, "Replay", nil), "Started")
		local replay = lastLine(h)
		has(replay, "intent=Replay")
		has(replay, "from=Arena to=Arena")
		has(replay, "server=Reserved(new")
		T.equal(h.travel.travel(1, "ToLobby"), "Done")
		local back = lastLine(h)
		has(back, "intent=ToLobby")
		has(back, "to=Lobby")
		has(back, "server=Public")
	end)

	test("Lobby button from the Simulator, and intents from the wrong Place are refused", function()
		local h = stub("Simulator", 1)
		T.equal(h.travel.travel(USER, "LobbyButton"), "Done")
		has(lastLine(h), "intent=LobbyButton")
		has(lastLine(h), "to=Lobby")
		local printedBefore = #h.printed
		for _, intent in { "Portal", "MatchStart", "Replay", "ToLobby", "LoadFailReturn" } do
			T.equal(h.travel.travel(USER, intent), "Refused", intent)
		end
		T.equal(#h.printed, printedBefore, "no stub teleport for refused intents")
		T.isTrue(TH.logged(h.logs, "Portal for P1001 refused: Portal is not valid from Simulator"))
	end)

	test("after a stub success the player stays with their session, so the next test can run", function()
		local h = stub("Simulator", 1)
		T.equal(h.travel.travel(USER, "WorldGate"), "Done")
		T.equal(h.server.core.getStatus(USER), "Loaded")
		T.equal(TH.stored(h).lockServer, "A")
		T.equal(h.travel.travel(USER, "LobbyButton"), "Done", "a second travel works")
	end)

	test("AC2 simulated failure (TravelFailTeleport): message, retry, success", function()
		local h = stub("Lobby")
		h.stubFailures = 1
		T.equal(h.travel.travel(USER, "Portal"), "Done")
		T.isTrue(TH.logged(h.printed, "attempt=1/3 -> simulated failure"))
		T.isTrue(TH.logged(h.printed, "attempt=2/3 -> ok"))
		T.equal(TH.noticeKeys(h)[1], "TeleportRetry")
		T.equal(h.server.core.getStatus(USER), "Loaded")
	end)

	test("AC2 simulated failure every time: the player stays with the final message", function()
		local h = stub("Lobby")
		h.stubFailures = 99
		T.equal(h.travel.travel(USER, "Portal"), "TeleportFailed")
		local keys = TH.noticeKeys(h)
		T.equal(keys[#keys], "TeleportFailed")
		T.equal(h.server.core.getStatus(USER), "Loaded")
		T.equal(TH.stored(h).lockServer, "A")
	end)
end)

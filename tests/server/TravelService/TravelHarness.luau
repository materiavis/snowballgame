--!strict
-- Builds a TravelCore wired to a real DataCore (DataService's Harness, fake DataStore), a real
-- ServerChoice over PresenceCore + FakeMemoryStore, and a scripted teleporter. Not a spec.
--
-- Teleport results are taken from `h.results` in order: true (the player leaves, like a real
-- successful teleport), or a failure reason string ("GameFull: full", "Timeout"). An empty
-- list means success. `h.onTeleport` runs inside each teleport, before the result, to
-- interleave another server or a fault. With `stub = true` the real StubTeleporter is used.

local H = require("../DataService/Harness")
local Destinations = require("../../../src/server/Services/TravelService/Destinations")
local FakeMemoryStore = require("../../../src/server/Services/PresenceStore/FakeMemoryStore")
local LoadFailReturn = require("../../../src/server/Services/TravelService/LoadFailReturn")
local LobbyConfig = require("../../../src/shared/Config/Lobby")
local Places = require("../../../src/shared/Config/Places")
local PresenceCore = require("../../../src/server/Services/PresenceStore/PresenceCore")
local ServerChoice = require("../../../src/server/Services/TravelService/ServerChoice")
local StubTeleporter = require("../../../src/server/Services/TravelService/StubTeleporter")
local TravelConfig = require("../../../src/shared/Config/Travel")
local TravelCore = require("../../../src/server/Services/TravelService/TravelCore")
local ZonesConfig = require("../../../src/shared/Config/Zones")

export type Call = { userId: number, dest: any, target: any, info: any }

local TravelHarness = {}

TravelHarness.Config = TravelConfig
TravelHarness.USER = H.USER

export type Options = {
	role: "Lobby" | "Simulator" | "Arena",
	worldIndex: number?,
	places: any?,
	stub: boolean?,
	saveFault: boolean?, -- start with DataFailSave on
	loadFault: boolean?, -- start with DataFailLoad on
	noLoad: boolean?, -- do not load USER
	users: { number }?,
}

function TravelHarness.new(options: Options)
	local world = H.world()
	local h: any = {
		world = world,
		calls = {} :: { Call },
		results = {} :: { any },
		notices = {} :: { { userId: number, key: string } },
		kicks = {} :: { string },
		logs = {} :: { string },
		printed = {} :: { string },
		events = {} :: { any },
		waits = {} :: { number },
		present = {} :: { [number]: boolean },
		friends = {} :: { number },
		privateKey = nil :: string?,
		reserves = 0,
		failSave = options.saveFault == true,
		failLoad = options.loadFault == true,
		stubFailures = 0,
		onTeleport = nil :: ((call: Call) -> ())?,
		onWait = nil :: ((seconds: number) -> ())?,
	}
	h.server = H.server(world, "A", function(purpose)
		if purpose == "Save" then
			return h.failSave
		end
		return h.failLoad
	end)
	local users = options.users or { H.USER }
	for _, userId in users do
		h.present[userId] = true
	end

	local function log(level: string, message: string)
		table.insert(h.logs, `{level}: {message}`)
	end
	local function wait(seconds: number)
		table.insert(h.waits, seconds)
		world.clock.advance(seconds)
		if h.onWait then
			h.onWait(seconds)
		end
	end

	h.presenceMap = FakeMemoryStore.newMap(world.clock.now)
	h.presence = PresenceCore.new({ map = h.presenceMap, wait = wait, log = log, config = TravelConfig })

	local function leave(userId: number)
		h.present[userId] = false
		h.server.core.release(userId, "Leave")
	end
	h.leave = leave

	local stub = StubTeleporter.new({
		print = function(line)
			table.insert(h.printed, line)
		end,
		shouldFail = function()
			if h.stubFailures > 0 then
				h.stubFailures -= 1
				return true
			end
			return false
		end,
		describeTarget = ServerChoice.describe,
	})

	local function teleport(userId: number, dest: any, target: any, info: any): (boolean, string?)
		local call = { userId = userId, dest = dest, target = table.clone(target), info = info }
		table.insert(h.calls, call)
		if h.onTeleport then
			h.onTeleport(call)
		end
		if options.stub then
			return stub.teleport(userId, dest, target, info)
		end
		local result = table.remove(h.results, 1)
		if result == nil or result == true then
			leave(userId)
			return true, nil
		end
		return false, result
	end

	local function reserve(placeId: number): (boolean, string?, string?)
		if options.stub then
			return stub.reserve(placeId)
		end
		h.reserves += 1
		return true, `code-{h.reserves}`, `psid-{h.reserves}`
	end

	h.destinations = Destinations.new({
		places = options.places or Places,
		zoneCount = ZonesConfig.ZoneCount,
		zonesPerWorld = ZonesConfig.ZonesPerWorld,
		role = options.role,
		worldIndex = options.worldIndex,
	})
	h.choice = ServerChoice.new({
		presence = h.presence,
		friendsOf = function()
			return h.friends
		end,
		reserve = reserve,
		privateKey = function()
			return h.privateKey
		end,
		maxSimulatorPlayers = LobbyConfig.SimulatorPlayers,
		ownJobId = "A",
		log = log,
	})
	local dataCore = h.server.core
	local deps = {
		role = options.role,
		destinations = h.destinations,
		choice = h.choice,
		describeTarget = ServerChoice.describe,
		data = {
			prepare = dataCore.prepareTeleport,
			resume = dataCore.resumeAfterTeleport,
			getStatus = dataCore.getStatus,
			getProfile = dataCore.getData,
		},
		teleport = teleport,
		notify = function(userId, key)
			table.insert(h.notices, { userId = userId, key = key })
		end,
		kick = function(userId, message)
			table.insert(h.kicks, message)
			leave(userId)
		end,
		isPresent = function(userId)
			return h.present[userId] == true
		end,
		nameOf = function(userId)
			return `P{userId}`
		end,
		wait = wait,
		spawn = function(fn)
			fn()
		end,
		log = log,
		allowUnpublished = options.stub == true,
		stayAfterSuccess = options.stub == true,
		config = TravelConfig,
	}
	h.travel = TravelCore.new(deps)
	h.loadFail = LoadFailReturn.new(deps, h.travel)
	h.travel.subscribe(function(event)
		table.insert(h.events, event)
	end)

	if not options.noLoad then
		for _, userId in users do
			dataCore.load(userId)
		end
	end
	return h
end

-- Published PlaceIds, so the live (non-stub) path accepts every destination.
TravelHarness.PUBLISHED = table.freeze({
	Lobby = 100,
	Arena = 300,
	Worlds = table.freeze({ [1] = 201, [2] = 202 }),
})

function TravelHarness.noticeKeys(h: any): { string }
	local out = {}
	for _, notice in h.notices do
		table.insert(out, notice.key)
	end
	return out
end

function TravelHarness.count(list: { string }, value: string): number
	local found = 0
	for _, item in list do
		if item == value then
			found += 1
		end
	end
	return found
end

function TravelHarness.stored(h: any, userId: number?): any
	return H.stored(h.world, userId or H.USER)
end

function TravelHarness.logged(lines: { string }, needle: string): boolean
	for _, line in lines do
		if string.find(line, needle, 1, true) then
			return true
		end
	end
	return false
end

return table.freeze(TravelHarness)

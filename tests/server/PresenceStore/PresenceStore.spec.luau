--!strict
-- PresenceStore (ADR 0003 "Cross-server ephemeral state", ADR 0010): the fake MemoryStore
-- behaves like the real one where it matters (TTL, copies, rejected values, outages), and the
-- core treats every value it reads back as untrusted.

local T = require("../../TestKit")
local FakeClock = require("../../helpers/FakeClock")
local FakeMemoryStore = require("../../../src/server/Services/PresenceStore/FakeMemoryStore")
local PresenceCore = require("../../../src/server/Services/PresenceStore/PresenceCore")
local TravelConfig = require("../../../src/shared/Config/Travel")

local function setUp()
	local clock = FakeClock.new(1000)
	local map = FakeMemoryStore.newMap(clock.now)
	local logs: { string } = {}
	local core = PresenceCore.new({
		map = map,
		wait = function(seconds)
			clock.advance(seconds)
		end,
		log = function(_level, message)
			table.insert(logs, message)
		end,
		config = TravelConfig,
	})
	return clock, map, core, logs
end

return T.suite("PresenceStore", function(test)
	test("fake map: values are copies and expire after their TTL", function()
		local clock = FakeClock.new(0)
		local map = FakeMemoryStore.newMap(clock.now)
		local value = { a = 1 }
		map:SetAsync("k", value, 10)
		value.a = 2
		local read = map:GetAsync("k")
		T.equal(read.a, 1, "stored a copy")
		read.a = 3
		T.equal(map:GetAsync("k").a, 1, "returned a copy")
		clock.advance(9.9)
		T.isTrue(map:GetAsync("k") ~= nil)
		clock.advance(0.1)
		T.equal(map:GetAsync("k"), nil, "gone after the TTL")
		T.equal(map:size(), 0)
	end)

	test("fake map: rejects what MemoryStore rejects and fails on demand", function()
		local map = FakeMemoryStore.newMap(FakeClock.new().now)
		T.throws(function()
			map:SetAsync("k", function() end, 10)
		end, "cannot store")
		T.throws(function()
			map:SetAsync("k", 1, 0)
		end, "expiration")
		T.throws(function()
			map:SetAsync("k", 1, 46 * 24 * 3600)
		end, "expiration")
		map:setFailing(true)
		T.throws(function()
			map:GetAsync("k")
		end, "injected")
	end)

	test("fake service: one map per name", function()
		local service = FakeMemoryStore.newService(FakeClock.new().now)
		T.equal(service:GetHashMap("A"), service:GetHashMap("A"))
		T.isTrue(service:GetHashMap("A") ~= service:GetHashMap("B"))
	end)

	test("presence: publish, read, refresh within the TTL, remove", function()
		local clock, _, core = setUp()
		T.equal(core.publishServer("J1", 1, { 5, 6 }), 3)
		T.equal(core.getUser(5).jobId, "J1")
		T.equal(core.getServer("J1").count, 2)
		clock.advance(TravelConfig.PresenceRefresh)
		core.publishServer("J1", 1, { 5 })
		clock.advance(TravelConfig.PresenceRefresh)
		T.isTrue(core.getUser(5) ~= nil, "refresh keeps it alive")
		T.equal(core.getUser(6), nil, "a player who left expires")
		core.removeUser(5)
		T.equal(core.getUser(5), nil)
		T.isTrue(TravelConfig.PresenceRefresh < TravelConfig.PresenceTtl, "refresh beats the TTL")
	end)

	test("values read back are validated", function()
		local _, map, core = setUp()
		map:SetAsync(TravelConfig.UserKeyPrefix .. "7", { world = "1", jobId = "J" }, 60)
		map:SetAsync(TravelConfig.UserKeyPrefix .. "8", { world = 1, jobId = "" }, 60)
		map:SetAsync(TravelConfig.ServerKeyPrefix .. "J", { world = 1, count = -1 }, 60)
		map:SetAsync(TravelConfig.ReservedKeyPrefix .. "P", 5, 60)
		T.equal(core.getUser(7), nil)
		T.equal(core.getUser(8), nil)
		T.equal(core.getServer("J"), nil)
		T.equal(core.getPrivateKey("P"), nil)
	end)

	test("an outage returns nothing and is logged after the configured attempts", function()
		local _, map, core, logs = setUp()
		core.setUser(5, 1, "J1")
		map:setFailing(true)
		T.equal(core.getUser(5), nil)
		T.equal(core.setUser(5, 1, "J1"), false)
		T.equal(#logs, 2)
		map:setFailing(false)
		T.equal(core.getUser(5).world, 1, "the entry survived the outage")
	end)

	test("private mapping is stored both ways with its own TTL", function()
		local clock, _, core = setUp()
		T.equal(core.setReserved("vip", 1, "code", "psid"), true)
		T.equal(core.getReserved("vip", 1).accessCode, "code")
		T.equal(core.getReserved("vip", 2), nil)
		T.equal(core.getPrivateKey("psid"), "vip")
		clock.advance(TravelConfig.PresenceTtl)
		T.isTrue(core.getReserved("vip", 1) ~= nil, "outlives presence")
		clock.advance(TravelConfig.PrivateMappingTtl)
		T.equal(core.getReserved("vip", 1), nil)
	end)
end)

--!strict
-- PresenceStore per-mode player counts (issue #37 AC4, ADR 0015): one MemoryStore entry per
-- portal mode, every server writes its own count with UpdateAsync, stale servers drop out,
-- values read back are untrusted, the entry stays under the size cap, and an outage is a nil
-- read (the label keeps its value) rather than an error.

local T = require("../../TestKit")
local FakeClock = require("../../helpers/FakeClock")
local FakeMemoryStore = require("../../../src/server/Services/PresenceStore/FakeMemoryStore")
local PresenceCore = require("../../../src/server/Services/PresenceStore/PresenceCore")
local TravelConfig = require("../../../src/shared/Config/Travel")

local function setUp(config: any?)
	local clock = FakeClock.new(5000)
	local map = FakeMemoryStore.newMap(clock.now)
	local core = PresenceCore.new({
		map = map,
		wait = clock.advance,
		log = function() end,
		now = clock.now,
		config = config or TravelConfig,
	})
	return clock, map, core
end

return T.suite("PresenceStore mode counts", function(test)
	test("fake map UpdateAsync: copy in, nil cancels, TTL applies", function()
		local clock = FakeClock.new(0)
		local map = FakeMemoryStore.newMap(clock.now)
		T.equal(
			map:UpdateAsync("k", function(old)
				T.equal(old, nil)
				return { n = 1 }
			end, 10).n,
			1
		)
		T.equal(
			map:UpdateAsync("k", function()
				return nil
			end, 10),
			nil,
			"cancelled"
		)
		T.equal(map:GetAsync("k").n, 1, "unchanged after a cancel")
		clock.advance(10)
		T.equal(map:GetAsync("k"), nil, "expired")
		T.throws(function()
			map:UpdateAsync("k", function()
				return {}
			end, 0)
		end, "expiration")
	end)

	test("counts add up over servers and a server overwrites its own count", function()
		local _, _, core = setUp()
		T.equal(core.getModeCount("Singleplayer"), 0, "no entry is 0")
		T.isTrue(core.setModeCount("Singleplayer", "A", 3))
		T.isTrue(core.setModeCount("Singleplayer", "B", 5))
		T.equal(core.getModeCount("Singleplayer"), 8)
		core.setModeCount("Singleplayer", "A", 1)
		T.equal(core.getModeCount("Singleplayer"), 6)
		T.equal(core.getModeCount("Multiplayer"), 0, "modes are separate")
		core.removeModeServer("Singleplayer", "B")
		T.equal(core.getModeCount("Singleplayer"), 1)
	end)

	test("servers older than PresenceTtl do not count", function()
		local clock, _, core = setUp()
		core.setModeCount("Singleplayer", "old", 9)
		clock.advance(TravelConfig.PresenceTtl - 1)
		core.setModeCount("Singleplayer", "new", 2)
		T.equal(core.getModeCount("Singleplayer"), 11)
		clock.advance(1)
		T.equal(core.getModeCount("Singleplayer"), 2, "old expired")
	end)

	test("bad arguments are refused and bad stored values ignored", function()
		local _, map, core = setUp()
		T.equal(core.setModeCount("Singleplayer", "A", -1), false)
		T.equal(core.setModeCount("Singleplayer", "A", 1.5), false)
		T.equal(core.setModeCount("Singleplayer", "", 1), false)
		T.equal(core.setModeCount("", "A", 1), false)
		map:SetAsync(TravelConfig.ModeKeyPrefix .. "Singleplayer", {
			good = { c = 4, t = 5000 },
			negative = { c = -3, t = 5000 },
			fraction = { c = 1.5, t = 5000 },
			text = { c = "9", t = 5000 },
			noTime = { c = 2 },
			notATable = 7,
		}, 60)
		T.equal(core.getModeCount("Singleplayer"), 4)
		map:SetAsync(TravelConfig.ModeKeyPrefix .. "Singleplayer", "garbage", 60)
		T.equal(core.getModeCount("Singleplayer"), 0)
		T.isTrue(core.setModeCount("Singleplayer", "A", 2), "a broken entry is replaced")
		T.equal(core.getModeCount("Singleplayer"), 2)
	end)

	test("at most ModeMaxServers servers per entry; the oldest go first", function()
		local config = table.clone(TravelConfig) :: any
		config.ModeMaxServers = 3
		local clock, _, core = setUp(config)
		for index = 1, 5 do
			core.setModeCount("Singleplayer", `S{index}`, index)
			clock.advance(1)
		end
		T.equal(core.getModeCount("Singleplayer"), 3 + 4 + 5, "S1 and S2 dropped")
		T.isTrue(TravelConfig.ModeMaxServers > 0 and TravelConfig.ModeMaxServers <= 400, "32 KB value limit")
	end)

	test("an outage is a nil read and a false write, never an error", function()
		local _, map, core = setUp()
		core.setModeCount("Singleplayer", "A", 3)
		map:setFailing(true)
		T.equal(core.getModeCount("Singleplayer"), nil)
		T.equal(core.setModeCount("Singleplayer", "A", 4), false)
		T.equal(core.removeModeServer("Singleplayer", "A"), false)
		map:setFailing(false)
		T.equal(core.getModeCount("Singleplayer"), 3)
	end)

	test("the Simulator counts towards the Singleplayer portal", function()
		T.equal(TravelConfig.SimulatorMode, "Singleplayer")
	end)
end)

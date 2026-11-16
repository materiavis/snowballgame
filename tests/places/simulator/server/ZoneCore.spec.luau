--!strict
-- ZoneCore (#39, concept 7.6 and 6.5, ADR 0009, ADR 0014): barrier prices from the formula
-- (AC1), the cap and map rule (AC7, AC8), adjacency, double taps (AC13), refusals for client
-- values (AC10), the zone teleport (AC4 on the server) and the start zone (6.5). Profiles are
-- schema v1 defaults; coins go through the real CurrencyCore.

local T = require("../../../TestKit")
local H = require("../../../server/DataService/Harness")
local E = require("../../../helpers/Economy")
local FakeClock = require("../../../helpers/FakeClock")
local CurrencyConfig = require("../../../../src/shared/Config/Currency")
local CurrencyCore = require("../../../../src/server/Services/CurrencyService/CurrencyCore")
local ZoneCore = require("../../../../src/places/simulator/server/ZoneService/ZoneCore")

local USER = 7
local R = ZoneCore.Refusal

type World = {
	core: ZoneCore.Core,
	currency: any,
	profile: any,
	clock: FakeClock.FakeClock,
	zones: { [number]: boolean },
	barriers: { [number]: boolean },
	events: { ZoneCore.Event },
	loaded: { value: boolean },
}

local function world(overrides: { [string]: any }?): World
	local profile = H.Schema.newProfile()
	local loaded = { value = true }
	local zones: { [number]: boolean } = {}
	local barriers: { [number]: boolean } = {}
	for zone = 1, 6 do
		zones[zone] = true
		barriers[zone] = true
	end
	local function getProfile(userId: number): any
		return if userId == USER and loaded.value then profile else nil
	end
	local currency = CurrencyCore.new({ config = CurrencyConfig :: any, getProfile = getProfile, log = function() end })
	local clock = FakeClock.new(100)
	local config = table.clone(E.Config.Zones) :: any
	for key, value in overrides or {} do
		config[key] = value
	end
	local core = ZoneCore.new({
		config = config,
		formulas = E.Zones,
		worldIndex = 1,
		map = {
			hasZone = function(zone: number): boolean
				return zones[zone] == true
			end,
			hasBarrier = function(zone: number): boolean
				return barriers[zone] == true
			end,
		},
		getProfile = getProfile,
		spendCoins = function(userId: number, amount: number, reason: string)
			return currency.spend(userId, "Coins", amount, reason)
		end,
		now = clock.now,
		log = function() end,
	})
	local events: { ZoneCore.Event } = {}
	core.subscribe(function(event)
		table.insert(events, event)
	end)
	return {
		core = core,
		currency = currency,
		profile = profile,
		clock = clock,
		zones = zones,
		barriers = barriers,
		events = events,
		loaded = loaded,
	}
end

local function rich(w: World)
	w.currency.add(USER, "Coins", 1e12, "Test")
end

return T.suite("ZoneCore (#39)", function(test)
	test("AC1: every barrier price is Formulas.Zones.barrierPrice of the zone it ends", function()
		-- Concept 7.6 table: barrier at the end of zone 1 about 320, zone 5 about 30K.
		T.equal(E.Zones.barrierPrice(1), 320)
		T.isTrue(math.abs(E.Zones.barrierPrice(5) - 30000) / 30000 < 0.05, "zone 5 about 30K")
		for zone = 2, 5 do
			local w = world()
			w.profile.sim.unlockedZones = {}
			for unlocked = 1, zone - 1 do
				w.profile.sim.unlockedZones[tostring(unlocked)] = true
			end
			local price = E.Zones.barrierPrice(zone - 1)
			w.currency.add(USER, "Coins", price, "Test")
			T.equal(w.core.purchase(USER, zone, "Remote"), true, `zone {zone}`)
			T.equal(w.currency.get(USER, "Coins"), 0, `exactly the formula price for zone {zone}`)
			T.equal(w.events[#w.events].price, price)
		end
	end)

	test("an unlock writes the set and highestZone, never lastZone", function()
		local w = world()
		rich(w)
		T.equal(w.core.purchase(USER, 2, "Remote"), true)
		T.equal(w.profile.sim.unlockedZones["2"], true, "string key (schema v1)")
		T.equal(w.profile.sim.highestZone, 2)
		T.equal(w.profile.sim.lastZone, 1)
		T.equal(table.concat(w.core.unlocked(USER) :: { number }, ","), "1,2")
	end)

	test("AC13 6.5: a double tap is one purchase", function()
		local w = world()
		w.currency.add(USER, "Coins", E.Zones.barrierPrice(1) * 2, "Test")
		T.equal(w.core.purchase(USER, 2, "Remote"), true)
		T.equal(select(2, w.core.purchase(USER, 2, "Remote")), R.AlreadyUnlocked)
		T.equal(w.currency.get(USER, "Coins"), E.Zones.barrierPrice(1), "charged once")
	end)

	test("AC2 server side: too few coins changes nothing", function()
		local w = world()
		w.currency.add(USER, "Coins", 319, "Test")
		T.equal(select(2, w.core.purchase(USER, 2, "Remote")), "Insufficient")
		T.equal(w.currency.get(USER, "Coins"), 319)
		T.equal(w.profile.sim.unlockedZones["2"], nil)
		T.equal(w.events[#w.events].price, 320, "the refusal names the price for the missing amount")
	end)

	test("only the next zone: skipping a barrier is refused", function()
		local w = world()
		rich(w)
		T.equal(select(2, w.core.purchase(USER, 3, "Remote")), R.NotAdjacent)
		T.equal(w.profile.sim.unlockedZones["3"], nil)
	end)

	test("AC8: with zone 6 in the map and the cap at 5 the zone 5 barrier stays closed", function()
		local w = world()
		rich(w)
		T.equal(E.Config.Zones.HighestOpenZone, 5, "Vertical Slice cap")
		T.isTrue(w.zones[6], "the test map has a valid zone 6")
		for zone = 2, 5 do
			T.equal(w.core.purchase(USER, zone, "Remote"), true, `zone {zone}`)
		end
		local coins = w.currency.get(USER, "Coins")
		T.equal(table.pack(w.core.barrierState(5))[2], R.Capped)
		T.equal(select(2, w.core.purchase(USER, 6, "Remote")), R.Capped)
		T.equal(w.currency.get(USER, "Coins"), coins, "no coins taken")
		T.equal(w.profile.sim.unlockedZones["6"], nil)
		for zone = 1, 4 do
			T.equal(w.core.barrierState(zone), true, `barrier {zone} opens`)
		end
	end)

	test("AC8: a barrier opens only if the next zone has a valid area with one start", function()
		local w = world({ HighestOpenZone = 10 })
		rich(w)
		w.zones[3] = false -- zone 3 missing, or 0 / 2 ZoneStart anchors
		T.equal(w.core.purchase(USER, 2, "Remote"), true)
		T.equal(table.pack(w.core.barrierState(2))[2], R.NotInMap)
		T.equal(select(2, w.core.purchase(USER, 3, "Remote")), R.NotInMap)
		w.zones[3] = true
		T.equal(w.core.purchase(USER, 3, "Remote"), true, "opens without a code change once the area is there")
	end)

	test("AC8: a missing or invalid cap closes every barrier", function()
		for _, cap in { nil, 0, 5.5, 51, "5", -1 } :: { any } do
			local w = world({ HighestOpenZone = cap })
			rich(w)
			T.equal(w.core.capValid(), false, tostring(cap))
			T.equal(select(2, w.core.purchase(USER, 2, "Remote")), R.NoCap, tostring(cap))
		end
	end)

	test("no bound barrier at the end of the zone before: refused", function()
		local w = world()
		rich(w)
		w.barriers[1] = false
		T.equal(select(2, w.core.purchase(USER, 2, "Remote")), R.NoBarrier)
	end)

	test("AC10: client values outside a barrier zone of this world are refused before the profile", function()
		local w = world()
		rich(w)
		for _, zone in { 0, 1, -2, 1.5, 0 / 0, math.huge, 11, 51, "2", nil, {} } :: { any } do
			T.equal(select(2, w.core.purchase(USER, zone, "Remote")), R.BadZone, tostring(zone))
		end
		T.equal(w.currency.get(USER, "Coins"), 1e12)
	end)

	test("world gate: zone 10 ends in a gate, not a barrier (#105)", function()
		local w = world({ HighestOpenZone = 50 })
		T.equal(table.pack(w.core.barrierState(10))[2], R.WorldGate)
		T.equal(table.pack(w.core.barrierState(50))[2], R.BadZone, "zone 50 is not in world 1")
	end)

	test("not loaded or broken profile: refused, nothing written", function()
		local w = world()
		rich(w)
		w.loaded.value = false
		T.equal(select(2, w.core.purchase(USER, 2, "Remote")), R.NotLoaded)
		w.loaded.value = true
		w.profile.sim.unlockedZones = "broken"
		T.equal(select(2, w.core.purchase(USER, 2, "Remote")), R.BadProfile)
		T.equal(w.core.unlocked(USER), nil)
	end)

	test("zone 1 is always unlocked; malformed entries are ignored", function()
		local w = world()
		w.profile.sim.unlockedZones = { ["3"] = true, ["x"] = true, ["4"] = false, [5] = true, ["99"] = true }
		T.equal(table.concat(w.core.unlocked(USER) :: { number }, ","), "1,3")
	end)

	test("AC4 server side: the zone teleport goes only to unlocked zones with a start", function()
		local w = world()
		rich(w)
		T.equal(select(2, w.core.teleport(USER, 2, "Remote")), R.NotUnlocked)
		T.equal(w.core.purchase(USER, 2, "Remote"), true)
		T.equal(w.core.teleport(USER, 2, "Remote"), true)
		w.clock.advance(E.Config.Zones.ZoneTeleportWait)
		w.zones[1] = false
		T.equal(select(2, w.core.teleport(USER, 1, "Remote")), R.NoStart)
		for _, zone in { 0, 1.5, 11, "1", nil } :: { any } do
			T.equal(select(2, w.core.teleport(USER, zone, "Remote")), R.BadZone, tostring(zone))
		end
	end)

	test("zone teleport: 3 s wait after a teleport", function()
		local w = world()
		T.equal(E.Config.Zones.ZoneTeleportWait, 3)
		T.equal(w.core.teleport(USER, 1, "Remote"), true)
		w.clock.advance(1)
		local ok, refusal, remaining = w.core.teleport(USER, 1, "Remote")
		T.equal(ok, false)
		T.equal(refusal, R.Wait)
		T.near(remaining :: number, 2, 1e-9)
		w.clock.advance(2)
		T.equal(w.core.teleport(USER, 1, "Remote"), true)
	end)

	test("6.5: entering a zone sets lastZone; the next start is there", function()
		local w = world()
		rich(w)
		T.equal(w.core.purchase(USER, 2, "Remote"), true)
		T.equal(w.core.purchase(USER, 3, "Remote"), true)
		T.equal(w.core.enter(USER, 2, "Walk"), true)
		T.equal(w.profile.sim.lastZone, 2)
		T.equal(w.core.current(USER), 2)
		T.equal(w.core.startZone(USER), 2)
		T.equal(select(2, w.core.enter(USER, 5, "Walk")), R.Locked, "a locked zone never counts")
		T.equal(w.profile.sim.lastZone, 2)
		w.zones[2] = false
		T.equal(w.core.startZone(USER), 3, "last zone without a start: highest unlocked with one")
	end)

	test("no zone areas at all: no start zone (Roblox spawn stays)", function()
		local w = world()
		for zone = 1, 6 do
			w.zones[zone] = false
		end
		T.equal(w.core.startZone(USER), nil)
	end)

	test("Studio reset: back to zone 1 only", function()
		local w = world()
		rich(w)
		T.equal(w.core.purchase(USER, 2, "Remote"), true)
		T.equal(w.core.enter(USER, 2, "Walk"), true)
		T.equal(w.core.resetUnlocks(USER, "StudioSwitch"), true)
		T.equal(table.concat(w.core.unlocked(USER) :: { number }, ","), "1")
		T.equal(w.profile.sim.lastZone, 1)
		T.equal(w.profile.sim.highestZone, 1)
	end)
end)

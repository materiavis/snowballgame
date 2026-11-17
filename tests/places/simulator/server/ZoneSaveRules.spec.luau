--!strict
-- Zones against DataService and the fake store (#39 AC3, AC13): the concept 6.5 rows that apply
-- to a barrier. ZoneService calls DataService.SaveNow right after a successful unlock (checked
-- by ZoneSource.spec); here that save is `server.core.save(USER, "Barrier")`, the same DataCore
-- call SaveNow makes. Coins go through the real CurrencyCore.

local T = require("../../../TestKit")
local H = require("../../../server/DataService/Harness")
local E = require("../../../helpers/Economy")
local CurrencyConfig = require("../../../../src/shared/Config/Currency")
local CurrencyCore = require("../../../../src/server/Services/CurrencyService/CurrencyCore")
local ZoneCore = require("../../../../src/places/simulator/server/ZoneService/ZoneCore")

local USER = H.USER
local PRICE = E.Zones.barrierPrice(1)

type Game = { currency: any, zones: ZoneCore.Core }

local function gameOn(server: H.Server): Game
	local function getProfile(userId: number): any
		return server.core.getData(userId)
	end
	local currency = CurrencyCore.new({ config = CurrencyConfig :: any, getProfile = getProfile, log = function() end })
	local zones = ZoneCore.new({
		config = E.Config.Zones :: any,
		formulas = E.Zones,
		worldIndex = 1,
		map = {
			hasZone = function(zone: number): boolean
				return zone <= 6
			end,
			hasBarrier = function(_zone: number): boolean
				return true
			end,
		},
		getProfile = getProfile,
		spendCoins = function(userId: number, amount: number, reason: string)
			return currency.spend(userId, "Coins", amount, reason)
		end,
		now = function()
			return 0
		end,
		log = function() end,
	})
	return { currency = currency, zones = zones }
end

-- The barrier path of ZoneService: purchase, then the immediate save.
local function buy(server: H.Server, g: Game, zone: number): (boolean, any, boolean?)
	local ok, result = g.zones.purchase(USER, zone, "Remote")
	if not ok then
		return ok, result, nil
	end
	return ok, result, server.core.save(USER, "Barrier")
end

local function stored(world: H.World): (number?, any)
	local record = H.stored(world, USER)
	if record == nil then
		return nil, nil
	end
	return record.data.sim.coins, record.data.sim
end

return T.suite("ZoneService save rules (6.5)", function(test)
	test("AC13 Sofort speichern: a paid barrier is in the store before any autosave", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", PRICE + 5, "Sell")
		local ok, _, saved = buy(server, g, 2)
		T.equal(ok, true)
		T.equal(saved, true)
		local coins, sim = stored(world)
		T.equal(coins, 5, "the spend is stored")
		T.equal(sim.unlockedZones["2"], true, "with the unlock, without an autosave")
		T.equal(sim.highestZone, 2)
	end)

	test("AC3: unlocked zones and the last zone survive a restart", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", 1e9, "Sell")
		for zone = 2, 5 do
			T.equal((buy(server, g, zone)), true, `zone {zone}`)
		end
		T.equal(g.zones.enter(USER, 4, "Walk"), true)
		T.equal(server.core.release(USER, "Leave"), true)

		local restarted = H.server(world, "B")
		restarted.core.load(USER)
		local again = gameOn(restarted)
		T.equal(table.concat(again.zones.unlocked(USER) :: { number }, ","), "1,2,3,4,5")
		T.equal(again.zones.startZone(USER), 4, "6.5: starts in the last visited zone")
		T.equal(select(2, again.zones.purchase(USER, 3, "Remote")), "AlreadyUnlocked")
	end)

	test("AC13 Speichern schlägt fehl: unlock and spend stay on the server together", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", PRICE, "Sell")
		server.core.autosaveAll()

		world.store:setFailing("UpdateAsync", true)
		local ok, _, saved = buy(server, g, 2)
		T.equal(ok, true, "the unlock stands in memory")
		T.equal(saved, false, "forced save failure")
		local coins, sim = stored(world)
		T.equal(coins, PRICE, "the store keeps the old balance")
		T.equal(sim.unlockedZones["2"], nil, "and no unlock: neither half was written")
		T.equal(g.zones.isUnlocked(USER, 2), true, "the zone stays open on this server")
		T.equal(g.currency.get(USER, "Coins"), 0)
		T.equal(server.core.getStatus(USER), "Loaded", "a failed save does not end the session")

		world.store:setFailing("UpdateAsync", false)
		server.core.autosaveAll()
		coins, sim = stored(world)
		T.equal(coins, 0, "the next save stores the spend")
		T.equal(sim.unlockedZones["2"], true, "together with the unlock")
	end)

	test("AC13: a save failure on leave keeps the lock; autosave stores the barrier later", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", PRICE, "Sell")
		world.store:setFailing("UpdateAsync", true)
		T.equal((buy(server, g, 2)), true)
		T.equal(server.core.release(USER, "Leave"), false)
		world.store:setFailing("UpdateAsync", false)
		server.core.autosaveAll()
		local coins, sim = stored(world)
		T.equal(coins, 0)
		T.equal(sim.unlockedZones["2"], true)
	end)

	test("AC13 Serverabsturz: a saved barrier is never lost, unsaved coins may be", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", PRICE, "Sell")
		T.equal(select(3, buy(server, g, 2)), true)
		g.currency.add(USER, "Coins", 77, "Sell") -- after the save; the crash loses it
		-- Crash: server A never writes again. B steals the lock once it has aged out.
		world.clock.advance(H.Config.LockTimeout + 1)
		local next = H.server(world, "B")
		T.equal(next.core.load(USER), "Loaded")
		local again = gameOn(next)
		T.equal(again.zones.isUnlocked(USER, 2), true, "the barrier survived the crash")
		T.equal(again.currency.get(USER, "Coins"), 0, "only the unsaved coins are gone")
	end)

	test("AC13 Doppelt angetippt: two requests, one purchase and one save of it", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", PRICE * 2, "Sell")
		local first = table.pack(buy(server, g, 2))
		local second = table.pack(buy(server, g, 2))
		T.equal(first[1], true)
		T.equal(second[2], "AlreadyUnlocked")
		local coins = stored(world)
		T.equal(coins, PRICE, "charged once")
	end)

	test("AC13 Laden: not loaded refuses and writes nothing", function()
		local world = H.world()
		local seed = H.server(world, "seed")
		local seeded = gameOn(seed)
		seed.core.load(USER)
		seeded.currency.add(USER, "Coins", 500, "Sell")
		seed.core.release(USER, "Leave")
		local before = H.stored(world, USER)

		world.store:setFailing("UpdateAsync", true)
		local server = H.server(world, "B")
		local g = gameOn(server)
		local attempt: string? = nil
		server.onWait = function()
			if server.core.getStatus(USER) == "Failed" and attempt == nil then
				attempt = select(2, g.zones.purchase(USER, 2, "Remote"))
				world.store:setFailing("UpdateAsync", false)
			end
		end
		T.equal(server.core.load(USER), "Loaded")
		T.equal(attempt, "NotLoaded")
		T.equal(g.zones.isUnlocked(USER, 2), false)
		T.equal(H.stored(world, USER).saveSeq, before.saveSeq, "nothing written")
	end)

	test("AC13: a server that lost the lock refuses unlocks and never writes them", function()
		local world = H.world()
		local first = H.server(world, "A")
		local g = gameOn(first)
		first.core.load(USER)
		g.currency.add(USER, "Coins", 1000, "Sell")
		first.core.autosaveAll()
		world.clock.advance(H.Config.LockTimeout + 1)
		local second = H.server(world, "B")
		second.core.load(USER)

		local ok, _, saved = buy(first, g, 2)
		T.equal(ok, true, "server A does not know yet")
		T.equal(saved, false, "its immediate save finds the lock gone")
		T.equal(first.core.getStatus(USER), "Lost")
		T.equal(select(2, g.zones.purchase(USER, 3, "Remote")), "NotLoaded")
		local coins, sim = stored(world)
		T.equal(coins, 1000, "the lost server's spend never reached the store")
		T.equal(sim.unlockedZones["2"], nil)
	end)
end)

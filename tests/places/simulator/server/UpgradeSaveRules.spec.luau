--!strict
-- Upgrades against DataService and the fake store (#36 AC4, AC9): the concept 6.5 rows that
-- apply to an upgrade purchase. The cores read profiles through DataCore.getData, exactly as the
-- Roblox layer does through DataService.GetProfile, and spend through the real CurrencyCore.

local T = require("../../../TestKit")
local H = require("../../../server/DataService/Harness")
local E = require("../../../helpers/Economy")
local CurrencyConfig = require("../../../../src/shared/Config/Currency")
local CurrencyCore = require("../../../../src/server/Services/CurrencyService/CurrencyCore")
local UpgradeCore = require("../../../../src/places/simulator/server/UpgradeService/UpgradeCore")

local USER = H.USER

type Game = { currency: any, upgrades: UpgradeCore.Core }

local function gameOn(server: H.Server): Game
	local function getProfile(userId: number): any
		return server.core.getData(userId)
	end
	local currency = CurrencyCore.new({ config = CurrencyConfig :: any, getProfile = getProfile, log = function() end })
	local upgrades = UpgradeCore.new({
		config = E.Config.Upgrades :: any,
		formulas = E.Upgrades,
		getProfile = getProfile,
		spendCoins = function(userId: number, amount: number, reason: string)
			return currency.spend(userId, "Coins", amount, reason)
		end,
		log = function() end,
	})
	return { currency = currency, upgrades = upgrades }
end

local function stored(world: H.World): (number?, any)
	local record = H.stored(world, USER)
	if record == nil then
		return nil, nil
	end
	return record.data.sim.coins, record.data.sim.upgrades
end

return T.suite("UpgradeService save rules (6.5)", function(test)
	test("AC4: a purchase lands with the next autosave and survives a restart", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", 100, "Sell")
		T.equal(g.upgrades.purchase(USER, "walkSpeed", "Remote"), true)
		T.equal(g.upgrades.purchase(USER, "growth", "Remote"), true)
		local _, before = stored(world)
		T.equal(before.walkSpeed, 0, "not an immediate save (ADR 0003)")

		server.core.autosaveAll()
		local coins, upgrades = stored(world)
		T.equal(coins, 100 - 40 - 25)
		T.equal(upgrades.walkSpeed, 1)
		T.equal(upgrades.growth, 1)
		T.equal(server.core.release(USER, "Leave"), true)

		local restarted = H.server(world, "B")
		restarted.core.load(USER)
		local again = gameOn(restarted)
		T.equal(again.upgrades.level(USER, "walkSpeed"), 1)
		T.equal(again.upgrades.level(USER, "growth"), 1)
		T.equal(again.upgrades.nextPrice(USER, "walkSpeed"), math.floor(40 * 1.35 * (1 + 1e-12)))
		T.equal(again.currency.get(USER, "Coins"), 35)
	end)

	test("AC4: level 100 is stored and loaded as 100", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		T.equal(g.upgrades.setLevel(USER, "stability", 100, "StudioSwitch"), true)
		T.equal(server.core.release(USER, "Leave"), true)
		local restarted = H.server(world, "B")
		restarted.core.load(USER)
		local again = gameOn(restarted)
		T.equal(again.upgrades.level(USER, "stability"), 100)
		T.equal(select(2, again.upgrades.purchase(USER, "stability", "Remote")), "MaxLevel")
	end)

	test("AC9 6.5 Speichern: a forced save failure keeps coins and level together on the server", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", 200, "Sell")
		server.core.autosaveAll()

		T.equal(g.upgrades.purchase(USER, "sellValue", "Remote"), true)
		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.save(USER, "Autosave"), false, "forced save failure")
		local coins, upgrades = stored(world)
		T.equal(coins, 200, "the store keeps the old balance")
		T.equal(upgrades.sellValue, 0, "and the old level: neither half was written")
		T.equal(g.currency.get(USER, "Coins"), 0, "the spend stays on the server")
		T.equal(g.upgrades.level(USER, "sellValue"), 1, "the level stays on the server")
		T.equal(server.core.getStatus(USER), "Loaded", "a failed save does not end the session")

		world.store:setFailing("UpdateAsync", false)
		T.equal(server.core.save(USER, "Retry"), true)
		coins, upgrades = stored(world)
		T.equal(coins, 0, "the next save stores the spend")
		T.equal(upgrades.sellValue, 1, "together with the level")
	end)

	test("AC9: a save failure on leave keeps the lock, and autosave stores both later", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", 150, "Sell")
		T.equal(g.upgrades.purchase(USER, "magnet", "Remote"), true)

		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.release(USER, "Leave"), false)
		world.store:setFailing("UpdateAsync", false)
		server.core.autosaveAll()
		local coins, upgrades = stored(world)
		T.equal(coins, 0)
		T.equal(upgrades.magnet, 1)
	end)

	test("AC9 6.5 Laden: buying while the profile is not loaded is refused and writes nothing", function()
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
				attempt = select(2, g.upgrades.purchase(USER, "growth", "Remote"))
				world.store:setFailing("UpdateAsync", false)
			end
		end
		T.equal(server.core.load(USER), "Loaded")
		T.equal(attempt, "NotLoaded")
		T.equal(g.upgrades.level(USER, "growth"), 0)
		T.equal(g.currency.get(USER, "Coins"), 500)
		T.equal(H.stored(world, USER).saveSeq, before.saveSeq, "nothing written")
	end)

	test("AC9: after the teleport hand-off or a release a purchase is refused", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", 500, "Sell")
		T.equal(server.core.prepareTeleport(USER), true)
		T.equal(select(2, g.upgrades.purchase(USER, "growth", "Remote")), "NotLoaded")
		local coins, upgrades = stored(world)
		T.equal(coins, 500)
		T.equal(upgrades.growth, 0)
	end)

	test("AC9: a server that lost the lock refuses purchases and never writes them", function()
		local world = H.world()
		local first = H.server(world, "A")
		local g = gameOn(first)
		first.core.load(USER)
		g.currency.add(USER, "Coins", 500, "Sell")
		first.core.autosaveAll()

		world.clock.advance(H.Config.LockTimeout + 1)
		local second = H.server(world, "B")
		second.core.load(USER)

		-- The first server learns it lost the lock on its next write.
		T.equal(g.upgrades.purchase(USER, "growth", "Remote"), true)
		first.core.autosaveAll()
		T.equal(first.core.getStatus(USER), "Lost")
		T.equal(select(2, g.upgrades.purchase(USER, "growth", "Remote")), "NotLoaded")
		local coins, upgrades = stored(world)
		T.equal(coins, 500, "the lost server's spend never reached the store")
		T.equal(upgrades.growth, 0, "nor its level")
	end)
end)

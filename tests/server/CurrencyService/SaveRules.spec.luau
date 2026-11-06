--!strict
-- CurrencyService against DataService and the fake store: the concept 6.5 rows that apply to
-- balances (issue #27 AC8). The core reads profiles through DataCore.getData, exactly as the
-- Roblox layer does through DataService.GetProfile.

local T = require("../../TestKit")
local H = require("../DataService/Harness")
local CurrencyConfig = require("../../../src/shared/Config/Currency")
local CurrencyCore = require("../../../src/server/Services/CurrencyService/CurrencyCore")

local USER = H.USER

local function currencyFor(server: H.Server)
	return CurrencyCore.new({
		config = CurrencyConfig :: any,
		getProfile = function(userId: number)
			return server.core.getData(userId)
		end,
		log = function() end,
	})
end

local function storedCoins(world: H.World): (number?, number?)
	local record = H.stored(world, USER)
	if record == nil then
		return nil, nil
	end
	return record.data.sim.coins, record.data.sim.totalCoins
end

return T.suite("CurrencyService save rules (6.5)", function(test)
	test("a change lands with the next autosave and survives a rejoin", function()
		local world = H.world()
		local server = H.server(world, "A")
		local currency = currencyFor(server)
		server.core.load(USER)
		currency.add(USER, "Coins", 500, "Sell")
		currency.spend(USER, "Coins", 320, "Barrier")
		T.equal(storedCoins(world), 0, "nothing stored before a save")
		server.core.autosaveAll()
		T.equal(storedCoins(world), 180)
		T.equal(server.core.release(USER, "Leave"), true)

		local next = H.server(world, "B")
		next.core.load(USER)
		local again = currencyFor(next)
		T.equal(again.get(USER, "Coins"), 180)
		T.equal(again.getTotal(USER, "Coins"), 500)
	end)

	test("6.5 Speichern: a change survives a failed save and lands with the next save", function()
		local world = H.world()
		local server = H.server(world, "A")
		local currency = currencyFor(server)
		server.core.load(USER)
		currency.add(USER, "Coins", 240, "Sell")
		currency.add(USER, "SnowCoins", 45, "MatchWin")

		world.store:setFailing("UpdateAsync", true)
		local ok = server.core.save(USER, "Barrier")
		T.equal(ok, false, "forced save failure")
		T.equal(storedCoins(world), 0, "the store still has the old value")
		T.equal(currency.get(USER, "Coins"), 240, "the change stays on the server")
		T.equal(server.core.getStatus(USER), "Loaded", "a failed save does not end the session")

		world.store:setFailing("UpdateAsync", false)
		T.equal(server.core.save(USER, "Retry"), true)
		local coins, total = storedCoins(world)
		T.equal(coins, 240)
		T.equal(total, 240)
		T.equal(H.stored(world, USER).data.fight.snowCoins, 45)
	end)

	test("6.5: the caller's immediate save (SaveNow) stores a purchase before it returns", function()
		local world = H.world()
		local server = H.server(world, "A")
		local currency = currencyFor(server)
		server.core.load(USER)
		currency.add(USER, "Coins", 400, "Sell")
		T.equal(currency.spend(USER, "Coins", 320, "Barrier:1"), true)
		T.equal(server.core.save(USER, "Barrier:1"), true)
		T.equal(storedCoins(world), 80)
	end)

	test("6.5 Laden: changes before the profile is loaded are refused and write nothing", function()
		local world = H.world()
		local seed = H.server(world, "seed")
		seed.core.load(USER)
		currencyFor(seed).add(USER, "Coins", 500, "Sell")
		seed.core.release(USER, "Leave")
		local before = H.stored(world, USER)

		world.store:setFailing("UpdateAsync", true)
		local server = H.server(world, "B")
		local currency = currencyFor(server)
		local attempts = {}
		server.onWait = function()
			if server.core.getStatus(USER) == "Failed" and #attempts == 0 then
				table.insert(attempts, (select(2, currency.add(USER, "Coins", 100, "Sell"))))
				table.insert(attempts, (select(2, currency.spend(USER, "Coins", 1, "Egg"))))
				world.store:setFailing("UpdateAsync", false)
			end
		end
		T.equal(server.core.load(USER), "Loaded")
		T.equal(attempts[1], "NotLoaded", "add while loading failed")
		T.equal(attempts[2], "NotLoaded", "spend while loading failed")
		T.equal(currency.get(USER, "Coins"), 500, "the saved balance, nothing added")
		T.equal(H.stored(world, USER).saveSeq, before.saveSeq, "nothing written")
	end)

	test("6.5: after release or teleport the balance is read-only", function()
		local world = H.world()
		local server = H.server(world, "A")
		local currency = currencyFor(server)
		server.core.load(USER)
		currency.add(USER, "Coins", 90, "Sell")
		T.equal(server.core.prepareTeleport(USER), true)
		T.equal(select(2, currency.add(USER, "Coins", 10, "Sell")), "NotLoaded", "after teleport hand-off")
		T.equal(storedCoins(world), 90)

		local other = H.server(world, "B")
		local otherCurrency = currencyFor(other)
		other.core.load(USER)
		other.core.release(USER, "Leave")
		T.equal(select(2, otherCurrency.spend(USER, "Coins", 10, "Egg")), "NotLoaded", "after release")
		T.equal(storedCoins(world), 90)
	end)

	test("6.5: a server that lost the lock refuses changes and never writes them", function()
		local world = H.world()
		local first = H.server(world, "A")
		local currency = currencyFor(first)
		first.core.load(USER)
		currency.add(USER, "Coins", 100, "Sell")
		first.core.autosaveAll()

		-- A second server steals the stale lock (first server stopped renewing).
		world.clock.advance(H.Config.LockTimeout + 1)
		local second = H.server(world, "B")
		second.core.load(USER)
		currencyFor(second).add(USER, "Coins", 5, "Sell")
		second.core.autosaveAll()
		local seq = H.stored(world, USER).saveSeq

		-- The first server's next save finds the foreign lock and marks the session lost.
		currency.add(USER, "Coins", 1000, "Sell")
		first.core.autosaveAll()
		T.equal(first.core.getStatus(USER), "Lost")
		T.equal(select(2, currency.add(USER, "Coins", 1, "Sell")), "NotLoaded", "lost session refuses")
		T.equal(storedCoins(world), 105, "only the new lock holder's balance is stored")
		T.equal(H.stored(world, USER).saveSeq, seq, "the lost server wrote nothing")
	end)
end)

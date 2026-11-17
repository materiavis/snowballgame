--!strict
-- Selling against DataService and the fake store (#38 AC11): the concept 6.5 rows that apply to
-- a sale. SellCore reads profiles through DataCore.getData, exactly as the Roblox layer does
-- through DataService.GetProfile, and credits through the real CurrencyCore.

local T = require("../../../TestKit")
local H = require("../../../server/DataService/Harness")
local E = require("../../../helpers/Economy")
local CurrencyConfig = require("../../../../src/shared/Config/Currency")
local SellConfig = require("../../../../src/shared/Config/Sell")
local CurrencyCore = require("../../../../src/server/Services/CurrencyService/CurrencyCore")
local SellCore = require("../../../../src/places/simulator/server/SellService/SellCore")
local SaleOverride = require("../../../../src/places/simulator/server/SellService/SaleOverride")

local USER = H.USER
local FLAGS = SaleOverride.flagNames(E.Config.Economy)
local ON = { touching = true, clear = false, held = true, zone = 1 }
local AWAY = { touching = false, clear = true, held = true, zone = nil }

type Game = { currency: any, sell: SellCore.Core, ball: { size: number, resets: number } }

local function gameOn(server: H.Server): Game
	local function getProfile(userId: number): any
		return server.core.getData(userId)
	end
	local currency = CurrencyCore.new({ config = CurrencyConfig :: any, getProfile = getProfile, log = function() end })
	local ball = { size = 2, resets = 0 }
	local sell = SellCore.new({
		economy = E.Economy,
		ballValue = E.Zones.ballValue,
		config = SellConfig,
		getProfile = getProfile,
		sizeMetres = function(): number?
			return ball.size
		end,
		resetBall = function(): boolean
			ball.resets += 1
			ball.size = 0.2
			return true
		end,
		petMultiplier = function(): any
			return nil
		end,
		sellValueLevel = function(): number
			return 0
		end,
		sellMultiplier = function(): number
			return 1
		end,
		bonusFlags = function(): any
			return SaleOverride.noFlags(FLAGS)
		end,
		addCoins = function(userId: number, amount: number, reason: string): (boolean, any)
			return currency.add(userId, "Coins", amount, reason)
		end,
		log = function() end,
	})
	return { currency = currency, sell = sell, ball = ball }
end

local function storedCoins(world: H.World): (number?, number?)
	local record = H.stored(world, USER)
	if record == nil then
		return nil, nil
	end
	return record.data.sim.coins, record.data.sim.totalCoins
end

-- One full zone 1 ball (80 coins), then off the plate again.
local function sellFullBall(g: Game)
	g.ball.size = 2
	local ok, sale = g.sell.step(USER, ON)
	T.equal(ok, true, "sold")
	T.equal(sale.coins, 80)
	g.sell.step(USER, AWAY)
end

return T.suite("SellService save rules (6.5)", function(test)
	test("AC11: a sale lands with the next autosave, not at once, and survives a restart", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		server.core.autosaveAll()
		sellFullBall(g)
		T.equal(g.currency.get(USER, "Coins"), 80)
		T.equal((storedCoins(world)), 0, "a sale is not an immediate save (6.5 list, ADR 0003)")

		server.core.autosaveAll()
		local coins, total = storedCoins(world)
		T.equal(coins, 80)
		T.equal(total, 80, "and counts for the TotalCoins board")
		T.equal(server.core.release(USER, "Leave"), true)

		local restarted = H.server(world, "B")
		restarted.core.load(USER)
		T.equal(gameOn(restarted).currency.get(USER, "Coins"), 80)
	end)

	test("AC11 6.5 Speichern: coins of a sale survive a forced save failure and land with the next save", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		server.core.autosaveAll()

		sellFullBall(g)
		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.save(USER, "Autosave"), false, "forced save failure")
		T.equal((storedCoins(world)), 0, "the store keeps the old balance; nothing older or empty is written")
		T.equal(g.currency.get(USER, "Coins"), 80, "the coins stay on the server")
		T.equal(server.core.getStatus(USER), "Loaded", "a failed save does not end the session")

		-- Selling goes on while saves fail.
		sellFullBall(g)
		T.equal(g.currency.get(USER, "Coins"), 160)

		world.store:setFailing("UpdateAsync", false)
		T.equal(server.core.save(USER, "Retry"), true)
		T.equal((storedCoins(world)), 160, "the next save stores both sales")
	end)

	test("AC11: a save failure on leave keeps the lock, and a later autosave stores the sale", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		sellFullBall(g)

		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.release(USER, "Leave"), false)
		world.store:setFailing("UpdateAsync", false)
		server.core.autosaveAll()
		T.equal((storedCoins(world)), 80)
	end)

	test("AC11 6.5 Laden: a sale while the profile is not loaded is refused; the ball keeps its size", function()
		local world = H.world()
		world.store:setFailing("UpdateAsync", true)
		local server = H.server(world, "A")
		local g = gameOn(server)
		local attempt: string? = nil
		server.onWait = function()
			if server.core.getStatus(USER) == "Failed" and attempt == nil then
				attempt = select(2, g.sell.step(USER, ON))
				world.store:setFailing("UpdateAsync", false)
			end
		end
		T.equal(server.core.load(USER), "Loaded")
		T.equal(attempt, SellCore.Refusal.NotLoaded)
		T.equal(g.ball.resets, 0, "the ball was not reset")
		T.equal(g.ball.size, 2)
		T.equal(g.currency.get(USER, "Coins"), 0)
		-- Latched: the player pushes the ball off and on again once loaded.
		g.sell.step(USER, AWAY)
		T.equal(g.sell.step(USER, ON), true)
	end)

	test("AC11: after the teleport hand-off or a lost lock a sale is refused and never stored", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		sellFullBall(g)
		T.equal(server.core.prepareTeleport(USER), true)
		T.equal(select(2, g.sell.step(USER, ON)), SellCore.Refusal.NotLoaded)
		T.equal(g.ball.resets, 1, "only the first sale reset the ball")
		T.equal((storedCoins(world)), 80, "the hand-off saved the first sale")

		local other = H.world()
		local first = H.server(other, "A")
		local lost = gameOn(first)
		first.core.load(USER)
		first.core.autosaveAll()
		other.clock.advance(H.Config.LockTimeout + 1)
		H.server(other, "B").core.load(USER)
		sellFullBall(lost) -- before the first server learns that it lost the lock
		first.core.autosaveAll()
		T.equal(first.core.getStatus(USER), "Lost")
		T.equal(select(2, lost.sell.step(USER, ON)), SellCore.Refusal.NotLoaded)
		local record = H.stored(other, USER)
		T.equal(record and record.data.sim.coins, 0, "the lost server's sale never reached the store")
	end)
end)

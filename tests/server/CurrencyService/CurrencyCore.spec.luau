--!strict
-- CurrencyCore rules (ADR 0007, issue #27 AC5/AC8): validation of every amount, no negative
-- balances, totals only grow, bounds, events for the analytics hook.

local T = require("../../TestKit")
local CurrencyConfig = require("../../../src/shared/Config/Currency")
local CurrencyCore = require("../../../src/server/Services/CurrencyService/CurrencyCore")

local USER = 7

local function setUp(profile: any?)
	local state = {
		profile = profile or { sim = { coins = 0, totalCoins = 0 }, fight = { snowCoins = 0 } },
		events = {},
		logs = {},
	}
	state.core = CurrencyCore.new({
		config = CurrencyConfig :: any,
		getProfile = function(userId: number)
			return if userId == USER then state.profile else nil
		end,
		log = function(level: string, message: string)
			table.insert(state.logs, `{level}: {message}`)
		end,
	})
	state.core.subscribe(function(event)
		table.insert(state.events, event)
	end)
	return state
end

return T.suite("CurrencyCore", function(test)
	test("add raises coins and total coins; spend lowers coins only", function()
		local s = setUp()
		T.equal(select(2, s.core.add(USER, "Coins", 500, "Sell")), 500)
		T.equal(select(2, s.core.spend(USER, "Coins", 320, "Barrier")), 180)
		T.equal(s.profile.sim.coins, 180)
		T.equal(s.profile.sim.totalCoins, 500, "total counts everything earned")
		T.equal(s.core.get(USER, "Coins"), 180)
		T.equal(s.core.getTotal(USER, "Coins"), 500)
	end)

	test("spending more than the balance is refused and changes nothing", function()
		local s = setUp()
		s.core.add(USER, "Coins", 100, "Sell")
		local ok, why = s.core.spend(USER, "Coins", 101, "Egg")
		T.equal(ok, false)
		T.equal(why, "Insufficient")
		T.equal(s.profile.sim.coins, 100)
		T.equal(s.core.spend(USER, "Coins", 100, "Egg"), true, "the exact balance can be spent")
		T.equal(s.profile.sim.coins, 0, "never below 0")
		T.equal(s.core.canAfford(USER, "Coins", 1), false)
	end)

	test("Coins and Snow Coins are separate (8.1)", function()
		local s = setUp()
		s.core.add(USER, "SnowCoins", 30, "MatchWin")
		T.equal(s.profile.fight.snowCoins, 30)
		T.equal(s.profile.sim.coins, 0)
		T.equal(s.profile.sim.totalCoins, 0)
		T.equal(select(2, s.core.spend(USER, "Coins", 10, "Shop")), "Insufficient", "Snow Coins never pay Coins")
		T.equal(s.core.getTotal(USER, "SnowCoins"), nil, "Snow Coins have no total")
	end)

	test("bad amounts are refused: NaN, infinity, negative, fractional, non-numbers", function()
		local s = setUp()
		s.core.add(USER, "Coins", 50, "Seed")
		for label, amount in { nan = 0 / 0, inf = math.huge, negInf = -math.huge, negative = -5, fraction = 1.5 } do
			T.equal(select(2, s.core.add(USER, "Coins", amount, "Bad")), "BadAmount", `add {label}`)
			T.equal(select(2, s.core.spend(USER, "Coins", amount, "Bad")), "BadAmount", `spend {label}`)
		end
		T.equal(select(2, s.core.add(USER, "Coins", "100" :: any, "Bad")), "BadAmount", "string")
		T.equal(select(2, s.core.add(USER, "Coins", nil :: any, "Bad")), "BadAmount", "nil")
		T.equal(s.profile.sim.coins, 50)
		T.equal(s.profile.sim.totalCoins, 50)
	end)

	test("amounts above MaxChange are refused; balances are held at MaxBalance", function()
		local s = setUp()
		local snow = CurrencyConfig.Currencies.SnowCoins
		T.equal(select(2, s.core.add(USER, "SnowCoins", snow.MaxChange + 1, "Bad")), "TooLarge")
		s.profile.fight.snowCoins = snow.MaxBalance - 5
		T.equal(select(2, s.core.add(USER, "SnowCoins", 10, "Win")), snow.MaxBalance)
		T.equal(s.events[#s.events].clamped, 5)
		T.isTrue(#s.logs > 0 and string.find(s.logs[#s.logs], "MaxBalance", 1, true) ~= nil, "logged")
	end)

	test("unknown currency, bad reason and a corrupt balance are refused", function()
		local s = setUp()
		T.equal(select(2, s.core.add(USER, "Gems", 1, "Bad")), "UnknownCurrency")
		T.equal(select(2, s.core.add(USER, "Coins", 1, "")), "BadReason")
		T.equal(select(2, s.core.add(USER, "Coins", 1, string.rep("x", 65))), "BadReason")
		T.equal(select(2, s.core.add(USER, "Coins", 1, 5 :: any)), "BadReason")
		local broken = setUp({ sim = { coins = 0 / 0, totalCoins = 0 }, fight = { snowCoins = 0 } })
		T.equal(select(2, broken.core.add(USER, "Coins", 1, "Sell")), "BadProfile")
		local noFight = setUp({ sim = { coins = 0, totalCoins = 0 } })
		T.equal(select(2, noFight.core.add(USER, "SnowCoins", 1, "Win")), "BadProfile")
	end)

	test("no profile (not loaded, released, lost) means no change", function()
		local s = setUp()
		T.equal(select(2, s.core.add(USER + 1, "Coins", 1, "Sell")), "NotLoaded")
		T.equal(select(2, s.core.spend(USER + 1, "Coins", 1, "Egg")), "NotLoaded")
		T.equal(select(2, s.core.reset(USER + 1, "Coins", "Rebirth")), "NotLoaded")
		T.equal(s.core.get(USER + 1, "Coins"), nil)
		T.equal(s.core.canAfford(USER + 1, "Coins", 0), false)
	end)

	test("reset (rebirth) clears coins and keeps the total", function()
		local s = setUp()
		s.core.add(USER, "Coins", 7500, "Sell")
		T.equal(s.core.reset(USER, "Coins", "Rebirth"), true)
		T.equal(s.profile.sim.coins, 0)
		T.equal(s.profile.sim.totalCoins, 7500)
		local event = s.events[#s.events]
		T.equal(event.kind, "Reset")
		T.equal(event.amount, 7500)
	end)

	test("events: Earn, Spend, Reset and Refused with balance, total and reason", function()
		local s = setUp()
		s.core.add(USER, "Coins", 80, "Sell")
		s.core.spend(USER, "Coins", 25, "Upgrade:growth")
		s.core.spend(USER, "Coins", 1000, "Barrier")
		s.core.add(USER, "Coins", 0, "Nothing")
		T.equal(#s.events, 3, "a zero change emits nothing")
		local earn, spend, refused = s.events[1], s.events[2], s.events[3]
		T.equal(earn.kind, "Earn")
		T.equal(earn.balance, 80)
		T.equal(earn.total, 80)
		T.equal(spend.kind, "Spend")
		T.equal(spend.reason, "Upgrade:growth")
		T.equal(spend.balance, 55)
		T.equal(refused.kind, "Refused")
		T.equal(refused.refusal, "Insufficient")
		T.equal(refused.operation, "Spend")
		T.equal(refused.balance, 55)
		T.equal(earn.operation, "Add")
		s.core.add(USER, "Coins", 0 / 0, "Bad")
		T.equal(s.events[#s.events].operation, "Add", "a refused add says so")
	end)

	test("a failing listener never blocks a change; unsubscribe stops events", function()
		local s = setUp()
		local unsubscribe = s.core.subscribe(function()
			error("analytics down")
		end)
		T.equal(s.core.add(USER, "Coins", 10, "Sell"), true)
		T.equal(s.profile.sim.coins, 10)
		T.isTrue(string.find(s.logs[1], "analytics down", 1, true) ~= nil, "listener error logged")
		unsubscribe()
		s.core.add(USER, "Coins", 10, "Sell")
		T.equal(#s.logs, 1, "the removed listener is not called")
	end)

	test("values up to Sx stay whole and spendable", function()
		local s = setUp()
		s.core.add(USER, "Coins", 4.6e21, "Sell")
		T.equal(s.core.spend(USER, "Coins", 4.5e21, "Barrier"), true)
		T.equal(s.profile.sim.coins, 4.6e21 - 4.5e21)
		T.equal(s.profile.sim.totalCoins, 4.6e21)
	end)
end)

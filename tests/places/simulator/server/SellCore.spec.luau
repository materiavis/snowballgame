--!strict
-- Selling at the scale (#38, concept 7.5, 8.3, ADR 0012): the coins of a sale, one sale per
-- visit, the reset to start size and the server-only inputs. SellCore runs with the real
-- Formulas and Config; the profile, ball, upgrade and coin add are plain test doubles.
-- The expected coins are computed here by hand from the concept text, not with saleCoins.

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local SellConfig = require("../../../../src/shared/Config/Sell")
local SellCore = require("../../../../src/places/simulator/server/SellService/SellCore")
local SaleOverride = require("../../../../src/places/simulator/server/SellService/SaleOverride")
local UpgradeCore = require("../../../../src/places/simulator/server/UpgradeService/UpgradeCore")

local USER = 7

local FLAGS = SaleOverride.flagNames(E.Config.Economy)

-- Concept 7.5 / 8.3, typed in from the concept: Coins = (10 * size^3 + finds) * pets *
-- rebirth (1 + 0.5 per rebirth) * Sell value (+5 % per level) * bonuses, where Double coins
-- x2, Coins boost x2 and Golden snow x3 multiply and VIP +10 % and Premium +10 % add.
-- Whole coins, rounded down (ADR 0007).
local function expected(size: number, finds: number, pets: number, rebirths: number, level: number, flags: any): number
	local multiplied = 1
	if flags.DoubleCoins then
		multiplied *= 2
	end
	if flags.CoinsBoost then
		multiplied *= 2
	end
	if flags.GoldenSnow then
		multiplied *= 3
	end
	local added = 0
	if flags.Vip then
		added += 0.1
	end
	if flags.Premium then
		added += 0.1
	end
	local rebirth = 1 + 0.5 * rebirths
	local upgrade = 1 + (6 - 1) * level / 100
	local bonus = multiplied * (1 + added)
	return math.floor((10 * size ^ 3 + finds) * pets * rebirth * upgrade * bonus * (1 + 1e-12))
end

type World = {
	core: SellCore.Core,
	profile: any,
	loaded: boolean,
	size: number?,
	pet: any,
	level: number,
	flags: any,
	refuseCoins: string?,
	balance: number,
	credited: { { amount: number, reason: string } },
	resets: number,
	events: { any },
}

local START = 0.2 -- zone 1 start size in metres (10 % of 2 m)

local function world(): World
	local w: World = {
		core = nil :: any,
		profile = { sim = { coins = 0, rebirths = 0 } },
		loaded = true,
		size = 2,
		pet = nil,
		level = 0,
		flags = SaleOverride.noFlags(FLAGS),
		refuseCoins = nil,
		balance = 0,
		credited = {},
		resets = 0,
		events = {},
	}
	w.core = SellCore.new({
		economy = E.Economy,
		ballValue = E.Zones.ballValue,
		config = SellConfig,
		getProfile = function(_userId: number): any
			return if w.loaded then w.profile else nil
		end,
		sizeMetres = function(_userId: number): number?
			return w.size
		end,
		resetBall = function(_userId: number): boolean
			w.resets += 1
			w.size = START
			return true
		end,
		petMultiplier = function(_userId: number): any
			return w.pet
		end,
		sellValueLevel = function(_userId: number): number
			return w.level
		end,
		sellMultiplier = function(_userId: number): number
			return E.Upgrades.effect("sellValue", w.level)
		end,
		bonusFlags = function(_userId: number): any
			return w.flags
		end,
		addCoins = function(_userId: number, amount: number, reason: string): (boolean, any)
			if w.refuseCoins then
				return false, w.refuseCoins
			end
			table.insert(w.credited, { amount = amount, reason = reason })
			w.balance += amount
			return true, w.balance
		end,
		log = function() end,
	})
	w.core.subscribe(function(event)
		table.insert(w.events, event)
	end)
	return w
end

local ON = { touching = true, clear = false, held = true, zone = 1 }
local NEAR = { touching = false, clear = false, held = true, zone = 1 }
local AWAY = { touching = false, clear = true, held = true, zone = nil }

-- Every subset of the five 8.3 flags.
local function everyFlagSet(): { any }
	local sets = {}
	for mask = 0, 2 ^ #FLAGS - 1 do
		local flags = SaleOverride.noFlags(FLAGS)
		for index, name in FLAGS do
			if math.floor(mask / 2 ^ (index - 1)) % 2 == 1 then
				flags[name] = true
			end
		end
		table.insert(sets, flags)
	end
	return sets
end

return T.suite("SellService.SellCore (7.5, 8.3)", function(test)
	test("AC6: the flags are the five bonuses of 8.3", function()
		T.equal(table.concat(FLAGS, ","), "CoinsBoost,DoubleCoins,GoldenSnow,Premium,Vip")
		T.equal(E.Economy.sellBonus({ DoubleCoins = true, CoinsBoost = true, GoldenSnow = true }), 12, "x2 x2 x3")
		T.near(E.Economy.sellBonus({ Vip = true, Premium = true }), 1.2, 1e-12, "VIP + Premium added")
		T.near(
			E.Economy.sellBonus(SaleOverride.parse("bonus=" .. table.concat(FLAGS, ","), FLAGS).flags :: any),
			14.4,
			1e-12
		)
	end)

	test("AC1 AC6: every bonus combination with every factor matches the concept formula", function()
		local cases = 0
		for _, flags in everyFlagSet() do
			for _, zone in { 1, 5, 10, 25 } do
				for _, fraction in { 0.37, 1 } do
					for _, factors in
						{
							{ finds = 0, pets = 1, rebirths = 0, level = 0 },
							{ finds = 37.5, pets = 2.5, rebirths = 3, level = 17 },
							{ finds = 1200, pets = 1.1, rebirths = 1, level = 100 },
						}
					do
						local w = world()
						local maxSize = E.Zones.maxSize(zone)
						local size = maxSize * 0.1 + maxSize * 0.9 * fraction
						w.size = size
						w.flags = flags
						w.pet = factors.pets
						w.profile.sim.rebirths = factors.rebirths
						w.level = factors.level
						if factors.finds > 0 then
							T.equal(w.core.addFindValue(USER, factors.finds), true)
						end
						local want = expected(size, factors.finds, factors.pets, factors.rebirths, factors.level, flags)
						local ok, sale = w.core.step(USER, ON)
						T.equal(ok, want >= 1, `sold zone {zone}`)
						if ok then
							T.equal(
								sale.coins,
								want,
								`zone {zone} fraction {fraction} {SaleOverride.describeFlags(flags)}`
							)
							T.equal(w.credited[1].amount, want, "exactly that amount is credited")
						end
						cases += 1
					end
				end
			end
		end
		T.equal(cases, 32 * 4 * 2 * 3)
	end)

	test("AC1: worked examples", function()
		local w = world()
		w.size = 2 -- a full zone 1 ball
		T.equal(select(2, w.core.step(USER, ON)).coins, 80, "7.6 table: full ball of zone 1")

		w = world()
		w.size = E.Zones.maxSize(5) -- 4.8828125 m
		w.flags = SaleOverride.parse("bonus=DoubleCoins,CoinsBoost,GoldenSnow,Vip,Premium", FLAGS).flags
		-- 10 * 4.8828125^3 = 1164.15...; * 12 * 1.2 = 16763.8 -> 16763
		T.equal(select(2, w.core.step(USER, ON)).coins, 16763)

		w = world()
		w.size = E.Zones.maxSize(7)
		w.level = 10 -- x1.5
		w.pet = 1.5
		-- 10 * 7.62939453125^3 = 4440.89...; * 1.5 * 1.5 = 9992.0 -> 9992: "+9.9K"
		local sale = select(2, w.core.step(USER, ON))
		T.equal(sale.coins, 9992)
		T.equal(E.NumberFormat.signed(sale.coins), "+9.9K", "AC2: shown as +9.9K")
		T.equal(E.NumberFormat.signed(3456), "+3.4K", "AC2: the concept's example")
	end)

	test("AC3: after a sale the ball is at start size and the finds are paid out", function()
		local w = world()
		w.size = 1.5
		T.isTrue(w.core.addFindValue(USER, 10))
		local ok, sale = w.core.step(USER, ON)
		T.equal(ok, true)
		T.equal(sale.coins, math.floor(10 * 1.5 ^ 3 + 10))
		T.equal(w.resets, 1, "BallService.ResetSize was called once")
		T.equal(w.size, START)
		T.equal(w.core.findsValue(USER), 0, "the finds left the ball with the sale")
		T.equal(w.credited[1].reason, SellConfig.CoinReason)
		T.equal(SellConfig.CoinReason, "Sale")
		T.equal(w.events[#w.events].kind, "Sale")
		T.equal(sale.balance, sale.coins, "the new balance from CurrencyService")
	end)

	test("AC4: selling works before the maximum, with the same formula", function()
		local w = world()
		w.size = START + (2 - START) * 0.5 -- half way in zone 1: 1.1 m
		local ok, sale = w.core.step(USER, ON)
		T.equal(ok, true)
		T.equal(sale.coins, math.floor(10 * 1.1 ^ 3 * (1 + 1e-12)), "13 coins")
		T.equal(sale.coins, 13)
	end)

	test("AC5: Sell value is unlocked and counts from the next sale on", function()
		T.equal(E.Config.Upgrades.Locked.sellValue, nil, "removed from Config.Upgrades.Locked")
		local profile =
			{ sim = { coins = 0, upgrades = { growth = 0, walkSpeed = 0, magnet = 0, sellValue = 0, stability = 0 } } }
		local upgrades = UpgradeCore.new({
			config = E.Config.Upgrades :: any,
			formulas = E.Upgrades,
			getProfile = function()
				return profile
			end,
			spendCoins = function()
				return true
			end,
			log = function() end,
		})
		T.equal(upgrades.isLocked("sellValue"), false)
		T.equal(upgrades.purchase(USER, "sellValue", "Remote"), true, "buyable")

		local w = world()
		w.size = 2
		T.equal(select(2, w.core.step(USER, ON)).sellMultiplier, 1)
		w.level = upgrades.levelOrZero(USER, "sellValue") -- what UpgradeService.GetLevel returns now
		w.core.step(USER, AWAY)
		w.size = 2
		local sale = select(2, w.core.step(USER, ON))
		T.near(sale.sellMultiplier, 1.05, 1e-12, "+5 % at level 1")
		T.equal(sale.sellValueLevel, 1)
		T.equal(sale.coins, 84, "80 * 1.05")
	end)

	test("one sale per visit: the ball has to leave the plate before the next sale", function()
		local w = world()
		T.equal(w.core.step(USER, ON), true)
		T.isTrue(w.core.isLatched(USER))
		w.size = 2 -- even a regrown ball on the plate is not sold again
		for _ = 1, 20 do
			T.equal(select(2, w.core.step(USER, ON)), SellCore.Refusal.Latched)
		end
		T.equal(select(2, w.core.step(USER, NEAR)), SellCore.Refusal.Latched, "near the plate is not off it")
		T.isTrue(w.core.isLatched(USER))
		T.equal(select(2, w.core.step(USER, AWAY)), SellCore.Refusal.Latched, "leaving releases it")
		T.equal(w.core.isLatched(USER), false)
		T.equal(w.core.step(USER, ON), true, "back on the plate: sold again")
		T.equal(#w.credited, 2)
	end)

	test("the owner must be at the ball: a ball alone on the plate waits for its owner", function()
		local w = world()
		local alone = { touching = true, clear = false, held = false, zone = 1 }
		T.equal(select(2, w.core.step(USER, alone)), SellCore.Refusal.NotHeld)
		T.equal(w.core.isLatched(USER), false, "not latched: nothing was attempted")
		T.equal(#w.credited, 0)
		T.equal(w.core.step(USER, ON), true, "sold once the owner arrives")
		T.equal(select(2, w.core.step(USER, AWAY)), SellCore.Refusal.Latched)
		T.equal(select(2, w.core.step(USER, AWAY)), SellCore.Refusal.NotTouching)
	end)

	test("a ball worth less than MinSaleCoins is not sold and keeps its size", function()
		local w = world()
		w.size = START -- 0.08 coins
		local ok, refusal = w.core.step(USER, ON)
		T.equal(ok, false)
		T.equal(refusal, SellCore.Refusal.TooSmall)
		T.equal(w.resets, 0)
		T.equal(#w.credited, 0)
		T.isTrue(w.core.isLatched(USER), "latched, so it is not retried every check")
		T.equal(w.events[#w.events].sale.coins, 0)
		T.equal(SellConfig.MinSaleCoins, 1)
	end)

	test("refusals change nothing: not loaded, no ball, broken rebirths, CurrencyService refusal", function()
		local w = world()
		w.loaded = false
		T.equal(select(2, w.core.sell(USER, 1)), SellCore.Refusal.NotLoaded)
		w.loaded = true
		w.size = nil
		T.equal(select(2, w.core.sell(USER, 1)), SellCore.Refusal.NoBall)
		w.size = 2
		for _, bad in { 1.5, -1, 0 / 0, math.huge, "2", nil } do
			w.profile.sim.rebirths = bad
			T.equal(select(2, w.core.sell(USER, 1)), SellCore.Refusal.BadProfile, tostring(bad))
		end
		w.profile = { sim = nil }
		T.equal(select(2, w.core.sell(USER, 1)), SellCore.Refusal.BadProfile, "no sim table")
		w.profile = { sim = { rebirths = 0 } }
		T.isTrue(w.core.addFindValue(USER, 5))
		w.refuseCoins = "NotLoaded"
		T.equal(select(2, w.core.sell(USER, 1)), "NotLoaded", "CurrencyService's refusal is passed on")
		T.equal(w.resets, 0, "the ball was never reset")
		T.equal(w.core.findsValue(USER), 5, "the finds stay in the ball")
		T.equal(#w.credited, 0)
	end)

	test("AC8: the pet multiplier is the server attribute when it is a finite number >= 1, else 1", function()
		T.equal(SellConfig.PetMultiplierAttribute, "PetMultiplier")
		for _, case in
			{
				{ nil, 1 },
				{ 2.5, 2.5 },
				{ 1, 1 },
				{ 0.5, 1 },
				{ 0, 1 },
				{ -3, 1 },
				{ 0 / 0, 1 },
				{ math.huge, 1 },
				{ "3", 1 },
				{ true, 1 },
			}
		do
			T.equal(SellCore.petMultiplierOf(case[1]), case[2], tostring(case[1]))
		end
		local w = world()
		w.pet = 0 / 0
		local sale = select(2, w.core.step(USER, ON))
		T.equal(sale.petMultiplier, 1)
		T.equal(sale.coins, 80)
	end)

	test("AC8: finds value from the #40 API is checked and capped", function()
		local w = world()
		for _, bad in { -1, 0 / 0, math.huge, -math.huge, "5", true, nil } do
			T.equal(select(2, w.core.addFindValue(USER, bad)), SellCore.Refusal.BadValue, tostring(bad))
		end
		T.equal(w.core.findsValue(USER), 0)
		T.isTrue(w.core.addFindValue(USER, 0))
		T.isTrue(w.core.addFindValue(USER, 2.5))
		T.isTrue(w.core.addFindValue(USER, 4))
		T.equal(w.core.findsValue(USER), 6.5, "summed")
		T.equal(select(2, w.core.addFindValue(USER, SellConfig.MaxFindsValue * 2)), SellCore.Refusal.TooLarge)
		T.equal(w.core.findsValue(USER), 6.5, "a refused add changes nothing")
	end)

	test("6.5: leaving loses the finds in the ball and the plate latch", function()
		local w = world()
		T.isTrue(w.core.addFindValue(USER, 50))
		w.core.step(USER, ON)
		T.isTrue(w.core.addFindValue(USER, 20))
		w.core.forget(USER)
		T.equal(w.core.findsValue(USER), 0)
		T.equal(w.core.isLatched(USER), false)
	end)

	test("Studio override replaces pets, rebirths and flags; the profile stays untouched", function()
		local w = world()
		w.size = 2
		local override = SaleOverride.parse("pet=2 rebirths=2 bonus=GoldenSnow,Vip", FLAGS)
		w.core.setOverride(override)
		local sale = select(2, w.core.step(USER, ON))
		T.equal(sale.petMultiplier, 2)
		T.equal(sale.rebirths, 2)
		T.equal(sale.rebirthMultiplier, 2)
		T.near(sale.bonus, 3.3, 1e-12)
		T.equal(sale.coins, expected(2, 0, 2, 2, 0, { GoldenSnow = true, Vip = true }))
		T.equal(sale.coins, 1056, "80 * 2 * 2 * 3.3")
		T.equal(w.profile.sim.rebirths, 0)
		w.core.setOverride(nil)
		w.core.step(USER, AWAY)
		w.size = 2
		T.equal(select(2, w.core.step(USER, ON)).coins, 80)
	end)

	test("a failing listener does not undo or block a sale", function()
		local w = world()
		w.core.subscribe(function()
			error("listener bug")
		end)
		T.equal(w.core.step(USER, ON), true)
		T.equal(#w.credited, 1)
		T.equal(w.resets, 1)
	end)
end)

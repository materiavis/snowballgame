--!strict
-- Selling, bonuses, finds, rebirth, income per minute and Snow Coins (concept 7.5, 7.7,
-- 7.10, 7.12, 7.20, 8.2, 8.3, 8.4; issue #27 AC1).

local T = require("../../TestKit")
local E = require("../../helpers/Economy")

local Economy = E.Economy
local Zones = E.Zones
local Upgrades = E.Upgrades

return T.suite("Formulas.Economy (7.5, 7.10, 8.2, 8.3)", function(test)
	test("7.5: a full zone 1 ball with nothing else sells for 80", function()
		T.equal(Economy.saleCoins({ size = Zones.maxSize(1) }), 80)
	end)

	test("7.5: the sale is (10 * size^3 + finds) * pets * rebirth * upgrade * bonuses", function()
		local size = 3.2
		local finds = Economy.findValue(4, "Rare") + Economy.findValue(4, "Common")
		local pets = E.Pets.totalMultiplier({ 0.4, 1.0, 2.0 }) -- x4.4
		local rebirth = Economy.rebirthMultiplier(2) -- x2.0
		local upgrade = Upgrades.effect("sellValue", 10) -- +50 %
		local bonus = Economy.sellBonus({ DoubleCoins = true, Vip = true, Premium = true })
		local exact = (10 * size ^ 3 + finds) * pets * rebirth * upgrade * bonus
		T.equal(
			Economy.saleCoins({
				size = size,
				findsValue = finds,
				petMultiplier = pets,
				rebirthMultiplier = rebirth,
				sellMultiplier = upgrade,
				bonus = bonus,
			}),
			math.floor(exact * (1 + 1e-12))
		)
	end)

	test("7.5: selling before the maximum uses the same formula", function()
		T.equal(Economy.saleCoins({ size = 1 }), 10)
		T.equal(Economy.saleCoins({ size = 0 }), 0)
	end)

	test("8.3 bonuses: x2, x2 and x3 multiply; VIP and Premium add (+10 % each = x1.2)", function()
		T.equal(Economy.sellBonus({}), 1)
		T.near(Economy.sellBonus({ Vip = true, Premium = true }), 1.2, 1e-12, "VIP + Premium")
		T.near(Economy.sellBonus({ Vip = true }), 1.1, 1e-12, "VIP")
		T.equal(Economy.sellBonus({ DoubleCoins = true, CoinsBoost = true, GoldenSnow = true }), 12)
		T.near(
			Economy.sellBonus({ DoubleCoins = true, CoinsBoost = true, GoldenSnow = true, Vip = true, Premium = true }),
			14.4,
			1e-9,
			"all"
		)
		T.equal(Economy.sellBonus({ DoubleCoins = false }), 1, "false flags do nothing")
		T.throws(function()
			Economy.sellBonus({ TripleCoins = true })
		end, "unknown bonus flag")
	end)

	test("7.7: find values are 2 / 5 / 15 / 50 / 200 % of a full ball of the zone", function()
		local full = Zones.fullBallValue(6)
		local shares = { Common = 0.02, Uncommon = 0.05, Rare = 0.15, Epic = 0.5, Legendary = 2 }
		for rarity, share in shares do
			T.near(Economy.findValue(6, rarity), share * full, 1e-9 * full, rarity)
		end
		T.throws(function()
			Economy.findValue(6, "Secret")
		end, "no find value")
	end)

	test("8.4 rebirth 1: from zone 10, costs 2 x barrier of zone 10 = ca. 7.5M, gives x1.5", function()
		T.equal(Economy.canRebirth(9), false)
		T.equal(Economy.canRebirth(10), true)
		T.equal(Economy.rebirthCost(10), 2 * Zones.barrierPrice(10))
		T.near(Economy.rebirthCost(10), 7.5e6, 7.5e6 * 0.05, "ca. 7.5M")
		T.equal(Economy.rebirthMultiplier(0), 1)
		T.equal(Economy.rebirthMultiplier(1), 1.5)
		T.equal(Economy.rebirthMultiplier(2), 2)
		T.equal(Economy.rebirthMultiplier(3), 2.5)
	end)

	test("7.10 ranks: one per rebirth, the last (Legend) from 8 rebirths", function()
		T.equal(Economy.rebirthRank(0), 1)
		T.equal(Economy.rebirthRank(1), 2)
		T.equal(Economy.rebirthRank(8), 9)
		T.equal(Economy.rebirthRank(30), 9)
	end)

	test("8.2: income per minute = full ball of the highest zone * multipliers", function()
		T.equal(Economy.incomePerMinute(1, 1), 80)
		T.near(Economy.incomePerMinute(10, 3), 3 * Zones.fullBallValue(10), 1e-6, "zone 10 x3")
		-- 7.12 day 1: 10 minutes of income.
		T.equal(Economy.minutesOfIncome(10, 1, 1), 800)
		T.equal(Economy.minutesOfIncome(10, 2, 1.5), math.floor(10 * 156.25 * 1.5))
	end)

	test("7.20 / 8.3 Snow Coins: win 30, loss 15, freeze 2, MVP +10, bonuses", function()
		T.equal(Economy.snowCoins({ won = true, freezes = 0, mvp = false }), 30)
		T.equal(Economy.snowCoins({ won = false, freezes = 0, mvp = false }), 15)
		T.equal(Economy.snowCoins({ won = true, freezes = 4, mvp = true }), 48)
		T.equal(Economy.snowCoins({ won = true, freezes = 0, mvp = false, flags = { DoubleSnowCoins = true } }), 60)
		T.equal(Economy.snowCoins({ won = true, freezes = 0, mvp = false, flags = { Vip = true, Premium = true } }), 36)
		T.equal(Economy.snowCoins({ won = false, freezes = 0, mvp = false, flags = { PrivateServer = true } }), 7)
		T.throws(function()
			Economy.snowCoins({ won = true, freezes = -1, mvp = false })
		end, "freezes")
	end)

	test("bad inputs are errors", function()
		T.throws(function()
			Economy.saleCoins({ size = 2, petMultiplier = 0 / 0 })
		end, "petMultiplier")
		T.throws(function()
			Economy.saleCoins({ size = 2, findsValue = -1 })
		end, "findsValue")
		T.throws(function()
			Economy.rebirthMultiplier(1.5)
		end, "whole number")
	end)
end)

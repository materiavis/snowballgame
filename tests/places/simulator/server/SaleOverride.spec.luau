--!strict
-- The SellFactorOverride Studio switch text and the bonus flag names (#38, ADR 0012).

local T = require("../../../TestKit")
local EconomyConfig = require("../../../../src/shared/Config/Economy")
local SaleOverride = require("../../../../src/places/simulator/server/SellService/SaleOverride")

local NAMES = SaleOverride.flagNames(EconomyConfig)

return T.suite("SellService.SaleOverride (ADR 0012)", function(test)
	test("flag names come from both bonus tables of Config.Economy; all off by default", function()
		T.equal(table.concat(NAMES, ","), "CoinsBoost,DoubleCoins,GoldenSnow,Premium,Vip")
		local none = SaleOverride.noFlags(NAMES)
		for _, name in NAMES do
			T.equal(none[name], false, name)
		end
		T.equal(SaleOverride.describeFlags(none), "")
		T.equal(SaleOverride.describeFlags({ Vip = true, DoubleCoins = true, GoldenSnow = false }), "DoubleCoins,Vip")
	end)

	test("empty text means no override", function()
		for _, text in { "", "   " } do
			local override, problem = SaleOverride.parse(text, NAMES)
			T.equal(override, nil)
			T.equal(problem, nil)
		end
	end)

	test("pet, rebirths and bonus are parsed", function()
		local override = SaleOverride.parse("pet=2.5 rebirths=3 bonus=DoubleCoins,Premium", NAMES) :: any
		T.equal(override.pet, 2.5)
		T.equal(override.rebirths, 3)
		T.equal(override.flags.DoubleCoins, true)
		T.equal(override.flags.Premium, true)
		T.equal(override.flags.Vip, false, "every other flag off")
		local none = SaleOverride.parse("bonus=none", NAMES) :: any
		T.equal(SaleOverride.describeFlags(none.flags), "")
		T.equal(none.pet, nil, "factors not named keep their real source")
	end)

	test("invalid text is refused with a reason", function()
		for _, text in
			{
				"pet=0.5",
				"pet=abc",
				"pet=inf",
				"rebirths=1.5",
				"rebirths=-1",
				"bonus=TripleCoins",
				"bonus=Vip,Nope",
				"luck=2",
				"pet=2 pet=3",
				"pet",
				"pet=",
			}
		do
			local override, problem = SaleOverride.parse(text, NAMES)
			T.equal(override, nil, text)
			T.isTrue(type(problem) == "string", `{text} has a reason`)
		end
		T.equal(select(2, SaleOverride.parse(5, NAMES)), "expected a string")
	end)
end)

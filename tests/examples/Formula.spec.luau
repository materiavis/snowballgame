--!strict
-- Example: exact-formula tests (concept 7.5), additive bonus stacking per ADR 0003 plan
-- revision 2 (docs/technical/0003-snow-rush-intake.md, line 375). Bases other than the
-- plan's own case are arbitrary test values, not game numbers. All checks use `==`.

local T = require("../TestKit")
local ExampleFormula = require("./fixtures/ExampleFormula")

return T.suite("Example formula (additive bonus stacking)", function(test)
	test("no bonus returns the base unchanged", function()
		T.equal(ExampleFormula.stackBonusesBp({}), 10000)
		T.equal(ExampleFormula.applyBonuses(250, {}), 250)
	end)

	test("ADR case: ×1.4 + ×2.0 + ×3.0 stacks to exactly ×4.4", function()
		T.equal(ExampleFormula.stackBonusesBp({ 14000, 20000, 30000 }), 44000)
		T.equal(ExampleFormula.applyBonuses(100, { 14000, 20000, 30000 }), 440)
		T.equal(ExampleFormula.applyBonuses(2500, { 14000, 20000, 30000 }), 11000)
	end)

	test("a single bonus applies as itself", function()
		T.equal(ExampleFormula.applyBonuses(100, { 14000 }), 140)
		T.equal(ExampleFormula.applyBonuses(100, { 30000 }), 300)
	end)

	test("bonus order does not change the result", function()
		local a = ExampleFormula.applyBonuses(100, { 14000, 20000, 30000 })
		local b = ExampleFormula.applyBonuses(100, { 30000, 14000, 20000 })
		T.equal(a, b)
	end)

	test("invalid input is rejected, not clamped", function()
		T.throws(function()
			ExampleFormula.applyBonuses(-1, {})
		end, "base must be")
		T.throws(function()
			ExampleFormula.applyBonuses(0 / 0, {})
		end, "base must be")
		T.throws(function()
			ExampleFormula.applyBonuses(10, { 20000, 0 })
		end, "bonus 2 must be a positive whole number")
		T.throws(function()
			ExampleFormula.applyBonuses(10, { 1.4 })
		end, "bonus 1 must be a positive whole number")
		T.throws(function()
			ExampleFormula.applyBonuses(10, { 2000, 2000 })
		end, "stacked multiplier must be positive")
	end)
end)

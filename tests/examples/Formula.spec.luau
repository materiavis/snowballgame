--!strict
-- Example: exact-formula tests (concept 7.5). The inputs are arbitrary test values chosen to
-- be exactly representable as doubles, so `==` is a fair check; they are not game numbers.

local T = require("../TestKit")
local ExampleFormula = require("./fixtures/ExampleFormula")

return T.suite("Example formula (multiplicative bonuses)", function(test)
	test("no bonus returns the base unchanged", function()
		T.equal(ExampleFormula.applyMultipliers(250, {}), 250)
	end)

	test("several bonuses multiply exactly", function()
		T.equal(ExampleFormula.applyMultipliers(100, { 2, 1.5, 4 }), 1200)
		T.equal(ExampleFormula.applyMultipliers(64, { 0.5, 0.25 }), 8)
	end)

	test("bonus order does not change the result", function()
		local a = ExampleFormula.applyMultipliers(40, { 1.25, 3, 2 })
		local b = ExampleFormula.applyMultipliers(40, { 2, 1.25, 3 })
		T.equal(a, b)
		T.equal(a, 300)
	end)

	test("invalid input is rejected, not clamped", function()
		T.throws(function()
			ExampleFormula.applyMultipliers(-1, {})
		end, "base must be")
		T.throws(function()
			ExampleFormula.applyMultipliers(10, { 2, 0 })
		end, "multiplier 2 must be positive")
		T.throws(function()
			ExampleFormula.applyMultipliers(0 / 0, {})
		end, "base must be")
	end)
end)

--!strict
-- EXAMPLE FIXTURE, NOT GAME CODE. Shows the shape of an exact-formula test (concept 7.5).
-- The real sell formula, how bonuses stack and how results are rounded are decided by the
-- economy-config feature and live in src/shared/Config; nothing here is a design value.

local ExampleFormula = {}

-- Multiplies a base value by every bonus multiplier. Rejects bad input instead of
-- clamping, so a broken caller shows up as an error in tests rather than a wrong payout.
function ExampleFormula.applyMultipliers(base: number, multipliers: { number }): number
	if base ~= base or base < 0 then
		error(`ExampleFormula: base must be a non-negative number, got {base}`, 2)
	end
	local result = base
	for index, multiplier in multipliers do
		if multiplier ~= multiplier or multiplier <= 0 then
			error(`ExampleFormula: multiplier {index} must be positive, got {multiplier}`, 2)
		end
		result *= multiplier
	end
	return result
end

return table.freeze(ExampleFormula)

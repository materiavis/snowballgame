--!strict
-- EXAMPLE FIXTURE, NOT GAME CODE. Shows the shape of an exact-formula test (concept 7.5).
-- Stacking follows ADR 0003 plan revision 2, verification plan
-- (docs/technical/0003-snow-rush-intake.md, line 375): "sell with bonuses
-- (×1.4 + ×2.0 + ×3.0 → ×4.4)", i.e. bonuses add up: total = 1 + Σ(bonus − 1).
-- The real sell formula, its inputs and its rounding come with the economy-config
-- issue (#27) and live in src/shared/Config; nothing here is a design value.
--
-- Multipliers are integer basis points (×1.4 = 14000) because decimals are not exact in
-- doubles: 1 + 0.4 + 1 + 2 only lands on 4.4 by luck, and 100 × that is 440.00000000000006.
-- Integer sums and products stay exact below 2^53.

local ExampleFormula = {}

ExampleFormula.BASIS_POINTS = 10000

local function isWholeNumber(value: number): boolean
	return value == value and value % 1 == 0
end

-- Total multiplier in basis points: 10000 + Σ(bonus − 10000).
function ExampleFormula.stackBonusesBp(bonusesBp: { number }): number
	local total = ExampleFormula.BASIS_POINTS
	for index, bonus in bonusesBp do
		if not isWholeNumber(bonus) or bonus <= 0 then
			error(`ExampleFormula: bonus {index} must be a positive whole number of basis points, got {bonus}`, 2)
		end
		total += bonus - ExampleFormula.BASIS_POINTS
	end
	-- Rejected instead of clamped, so a broken caller shows up as an error, not a wrong payout.
	if total <= 0 then
		error(`ExampleFormula: stacked multiplier must be positive, got {total} bp`, 2)
	end
	return total
end

-- base × stacked multiplier. Exact whenever the true result is a whole number; how
-- fractional results are rounded is a design decision for the real formula.
function ExampleFormula.applyBonuses(base: number, bonusesBp: { number }): number
	if not isWholeNumber(base) or base < 0 then
		error(`ExampleFormula: base must be a non-negative whole number, got {base}`, 2)
	end
	return base * ExampleFormula.stackBonusesBp(bonusesBp) / ExampleFormula.BASIS_POINTS
end

return table.freeze(ExampleFormula)

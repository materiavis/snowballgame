--!strict
-- Compares observed roll counts with configured weights in percentage points.
-- Shared so every chance table (eggs, finds, ...) is held to the same check (concept 4.4).

local Distribution = {}

export type Row = { id: string, expectedPct: number, observedPct: number, deltaPp: number }

-- Errors when any outcome is more than `tolerancePp` percentage points off, when an outcome
-- appears that has no weight, or when the counts do not add up to `total` (a lost roll).
function Distribution.assertWithin(
	counts: { [string]: number },
	weights: { [string]: number },
	total: number,
	tolerancePp: number
): { Row }
	local weightSum = 0
	for _, weight in weights do
		weightSum += weight
	end
	assert(weightSum > 0, "Distribution: weights must sum to more than 0")

	local countSum = 0
	for id, count in counts do
		if weights[id] == nil then
			error(`Distribution: outcome {id} was rolled but has no weight`, 2)
		end
		countSum += count
	end
	if countSum ~= total then
		error(`Distribution: counts add up to {countSum}, expected {total}`, 2)
	end

	local rows: { Row } = {}
	for id, weight in weights do
		local expectedPct = weight / weightSum * 100
		local observedPct = (counts[id] or 0) / total * 100
		table.insert(
			rows,
			{ id = id, expectedPct = expectedPct, observedPct = observedPct, deltaPp = observedPct - expectedPct }
		)
	end
	-- Sorted before picking the worst row so ties report the same outcome on every run.
	table.sort(rows, function(a, b)
		return a.id < b.id
	end)

	local worst: Row? = nil
	for _, row in rows do
		if worst == nil or math.abs(row.deltaPp) > math.abs(worst.deltaPp) then
			worst = row
		end
	end

	if worst and math.abs(worst.deltaPp) > tolerancePp then
		error(
			string.format(
				"Distribution: %s observed %.2f%%, expected %.2f%% (%.2f pp, limit %.2f pp)",
				worst.id,
				worst.observedPct,
				worst.expectedPct,
				worst.deltaPp,
				tolerancePp
			),
			2
		)
	end

	return rows
end

return table.freeze(Distribution)

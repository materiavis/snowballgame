--!strict
-- Weighted pick from a chance table. Pure: the roll in [0, 1) comes from the caller, so tests
-- pass a seeded generator and the server passes Random (Rng/init.luau).

export type Entry = { id: string, weight: number }

local Weighted = {}

-- Errors on an empty table, a negative or non-finite weight, or a zero total, so a broken
-- table never silently picks the first entry.
function Weighted.total(entries: { Entry }): number
	assert(#entries > 0, "Rng.Weighted: table is empty")
	local total = 0
	for _, entry in entries do
		local weight = entry.weight
		assert(
			type(weight) == "number" and weight == weight and weight >= 0 and weight < math.huge,
			`Rng.Weighted: weight of {entry.id} must be a finite number >= 0`
		)
		total += weight
	end
	assert(total > 0, "Rng.Weighted: weights add up to 0")
	return total
end

function Weighted.pick(entries: { Entry }, roll: number): string
	assert(type(roll) == "number" and roll >= 0 and roll < 1, `Rng.Weighted: roll must be in [0, 1), got {roll}`)
	local target = roll * Weighted.total(entries)
	local cumulative = 0
	local last: string? = nil
	for _, entry in entries do
		if entry.weight > 0 then
			cumulative += entry.weight
			last = entry.id
			if target < cumulative then
				return entry.id
			end
		end
	end
	-- Float rounding can leave target a hair above the sum; that belongs to the last entry.
	return last :: string
end

return table.freeze(Weighted)

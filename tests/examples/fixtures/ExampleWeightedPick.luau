--!strict
-- EXAMPLE FIXTURE, NOT GAME CODE. Shows the shape of a chance-table roll (concept 4.4).
-- Real egg and find odds come from src/shared/Config via the economy-config feature.
-- The roll is a parameter, not drawn inside, so tests can feed a seeded generator.

export type Entry = { id: string, weight: number }

local ExampleWeightedPick = {}

-- `roll` is uniform in [0, 1). Entries are an array so the cumulative order is stable.
function ExampleWeightedPick.pick(entries: { Entry }, roll: number): string
	assert(#entries > 0, "ExampleWeightedPick: entries must not be empty")
	assert(roll >= 0 and roll < 1, "ExampleWeightedPick: roll must be in [0, 1)")

	local total = 0
	for _, entry in entries do
		assert(entry.weight > 0, `ExampleWeightedPick: weight of {entry.id} must be positive`)
		total += entry.weight
	end

	local target = roll * total
	local cumulative = 0
	for _, entry in entries do
		cumulative += entry.weight
		if target < cumulative then
			return entry.id
		end
	end
	-- Floating-point sums can leave target a hair above the final bound.
	return entries[#entries].id
end

return table.freeze(ExampleWeightedPick)

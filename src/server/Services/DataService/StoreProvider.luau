--!strict
-- Picks the store backend before anything touches DataStoreService (CLAUDE.md §9, ADR 0003).
-- The real service is passed in as a function and only called for a published Place, so at
-- PlaceId 0 not even GetService("DataStoreService") runs. Pure, no requires.

export type Mode = "Fake" | "Real"

local StoreProvider = {}

function StoreProvider.select(placeId: number, getRealService: () -> any, makeFakeService: () -> any): (any, Mode)
	if placeId == 0 then
		return makeFakeService(), "Fake"
	end
	return getRealService(), "Real"
end

return table.freeze(StoreProvider)

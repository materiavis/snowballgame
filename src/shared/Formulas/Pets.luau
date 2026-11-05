--!strict
-- Egg prices, pet bonuses, equip slots and inventory expansion (concept 7.9, 8.3, Q11).
-- Pure; Formulas/init.luau binds it to Config.Pets and the zone formulas.
--
-- A pet's bonus is what it adds to the multiplier; the "×1.1" shown for the common pet of
-- egg 1 is 1 + bonus. Equipped pets add up: total = 1 + bonus 1 + bonus 2 + ...

-- The zone formulas this module needs (Formulas/Zones). Declared here, not required, so the
-- module has no requires and loads the same under Lune and Roblox.
type ZoneValues = { fullBallValue: (zone: number) -> number }

export type PetsConfig = {
	EggZones: { number },
	EggPriceBalls: number,
	CommonBonusBase: number,
	CommonBonusGrowth: number,
	RarityPower: { [string]: number },
	SecretPetPower: number,
	FrostyBonus: number,
	VariantMultipliers: { [string]: number },
	SlotsStart: number,
	SlotsByZone: { { Zone: number, Slots: number } },
	SlotsGamepass: number,
	SlotsMax: number,
	InventoryExpansionSlots: number,
	InventoryExpansionPriceBalls: number,
	InventoryExpansionMax: number,
}

export type Pet = {
	egg: number,
	rarity: string, -- a Config.Rarity id; "Secret" is the Golden Yeti of that egg
	variant: string?, -- "normal" (default) | "gold" | "rainbow"
	frosty: boolean?,
}

export type Pets = {
	eggCount: number,
	eggZone: (egg: number) -> number,
	eggPrice: (egg: number) -> number,
	petBonus: (pet: Pet) -> number,
	totalMultiplier: (bonuses: { number }) -> number,
	equipSlots: (highestZone: number, hasGamepass: boolean) -> number,
	inventoryExpansionPrice: (highestZone: number) -> number,
	canExpandInventory: (currentSize: number) -> boolean,
}

-- Whole coins, rounded down. The tiny relative nudge keeps a product that should be whole
-- (79.99999999999999 from float maths) from losing a coin; it is far below one coin.
local function wholeCoins(value: number): number
	return math.floor(value * (1 + 1e-12))
end

local PetsFormulas = {}

function PetsFormulas.new(config: PetsConfig, zones: ZoneValues): Pets
	local eggCount = #config.EggZones

	local function eggZone(egg: number): number
		local zone = config.EggZones[egg]
		if type(egg) ~= "number" or zone == nil then
			error(`Formulas.Pets: egg must be 1..{eggCount}, got {tostring(egg)}`, 3)
		end
		return zone
	end

	-- EggPriceBalls full balls of the egg's zone, whole coins rounded down.
	local function eggPrice(egg: number): number
		return wholeCoins(config.EggPriceBalls * zones.fullBallValue(eggZone(egg)))
	end

	local function petBonus(pet: Pet): number
		eggZone(pet.egg) -- validates the egg index
		local commonBonus = config.CommonBonusBase * config.CommonBonusGrowth ^ (pet.egg - 1)
		local power: number
		if pet.rarity == "Secret" then
			power = config.SecretPetPower * config.RarityPower.Legendary
		else
			local found = config.RarityPower[pet.rarity]
			if found == nil then
				error(`Formulas.Pets: unknown rarity {tostring(pet.rarity)}`, 2)
			end
			power = found
		end
		local variant = config.VariantMultipliers[pet.variant or "normal"]
		if variant == nil then
			error(`Formulas.Pets: unknown variant {tostring(pet.variant)}`, 2)
		end
		local frosty = if pet.frosty then 1 + config.FrostyBonus else 1
		return commonBonus * power * variant * frosty
	end

	local function totalMultiplier(bonuses: { number }): number
		local total = 1
		for _, bonus in bonuses do
			total += bonus
		end
		return total
	end

	local function equipSlots(highestZone: number, hasGamepass: boolean): number
		local slots = config.SlotsStart
		for _, step in config.SlotsByZone do
			if highestZone >= step.Zone then
				slots += step.Slots
			end
		end
		if hasGamepass then
			slots += config.SlotsGamepass
		end
		return math.min(slots, config.SlotsMax)
	end

	-- Q11 default: InventoryExpansionPriceBalls full balls of the highest unlocked zone.
	local function inventoryExpansionPrice(highestZone: number): number
		return wholeCoins(config.InventoryExpansionPriceBalls * zones.fullBallValue(highestZone))
	end

	local function canExpandInventory(currentSize: number): boolean
		return currentSize + config.InventoryExpansionSlots <= config.InventoryExpansionMax
	end

	return table.freeze({
		eggCount = eggCount,
		eggZone = eggZone,
		eggPrice = eggPrice,
		petBonus = petBonus,
		totalMultiplier = totalMultiplier,
		equipSlots = equipSlots,
		inventoryExpansionPrice = inventoryExpansionPrice,
		canExpandInventory = canExpandInventory,
	})
end

return table.freeze(PetsFormulas)

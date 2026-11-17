--!strict
-- Pet catalogue lookups (concept 7.9, ADR 0013). Pure: Config.Pets, Config.Eggs, the rarity
-- order and Formulas.Pets.petBonus are passed to new(); PetCatalogue/init.luau binds them.
-- Shared by server (hatch, inventory, multiplier) and client (window, station label, followers).
--
-- A broken catalogue is an error at load, so a typo never reaches a hatch.

export type PetInfo = {
	id: string,
	name: string,
	egg: number,
	rarity: string,
}

-- A saved pet (sim.pets[uid], save format v1): kind, variant, frosty, equipped.
export type Record = { kind: any, variant: any, frosty: any, equipped: any }

export type PetsConfig = {
	EggZones: { number },
	Odds: { [string]: number },
	VariantMultipliers: { [string]: number },
	Catalogue: { [string]: { Name: string, Egg: number, Rarity: string } },
}

export type EggsConfig = {
	Available: { [number]: { Name: string } },
}

export type PetBonus = (pet: { egg: number, rarity: string, variant: string?, frosty: boolean? }) -> number

export type Catalogue = {
	-- Every pet id, by egg, then rarity (lowest first), then id.
	ids: { string },
	isKind: (kind: any) -> boolean,
	get: (kind: string) -> PetInfo?,
	petFor: (egg: number, rarity: string) -> string?,
	-- Pets of an egg, lowest rarity first.
	petsOf: (egg: number) -> { PetInfo },
	-- True when the egg is in Config.Eggs.Available and has a pet for every rarity it can roll.
	isAvailable: (egg: any) -> boolean,
	eggName: (egg: number) -> string?,
	-- The egg whose station sits in this zone (Config.Pets.EggZones), or nil.
	eggForZone: (zone: any) -> number?,
	-- The record's bonus, or nil when the record is not a valid pet.
	bonusOf: (record: any) -> number?,
	-- "1.15" from 1.15, "1.1" from 1.1, "4.4" from 4.4: at most `decimals`, trailing zeros dropped.
	multiplierText: (value: number, decimals: number) -> string,
}

local Catalogue = {}

local function isWhole(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0
end

function Catalogue.new(pets: PetsConfig, eggs: EggsConfig, rarityOrder: { string }, petBonus: PetBonus): Catalogue
	local rank: { [string]: number } = {}
	for index, id in rarityOrder do
		rank[id] = index
	end

	local infos: { [string]: PetInfo } = {}
	local byEgg: { [number]: { [string]: string } } = {}
	for id, entry in pets.Catalogue do
		assert(type(id) == "string" and string.match(id, "^%a[%w]*$") ~= nil, `PetCatalogue: bad pet id {tostring(id)}`)
		assert(type(entry.Name) == "string" and entry.Name ~= "", `PetCatalogue: {id} needs a Name`)
		assert(
			isWhole(entry.Egg) and pets.EggZones[entry.Egg] ~= nil,
			`PetCatalogue: {id} has an unknown Egg {tostring(entry.Egg)}`
		)
		assert(rank[entry.Rarity] ~= nil, `PetCatalogue: {id} has an unknown Rarity {tostring(entry.Rarity)}`)
		local slot = byEgg[entry.Egg] or {}
		assert(slot[entry.Rarity] == nil, `PetCatalogue: egg {entry.Egg} has two {entry.Rarity} pets`)
		slot[entry.Rarity] = id
		byEgg[entry.Egg] = slot
		infos[id] = table.freeze({ id = id, name = entry.Name, egg = entry.Egg, rarity = entry.Rarity })
	end

	local ids: { string } = {}
	for id in infos do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string): boolean
		local x, y = infos[a], infos[b]
		if x.egg ~= y.egg then
			return x.egg < y.egg
		end
		if x.rarity ~= y.rarity then
			return rank[x.rarity] < rank[y.rarity]
		end
		return a < b
	end)

	local available: { [number]: boolean } = {}
	for egg, entry in eggs.Available do
		assert(
			isWhole(egg) and pets.EggZones[egg] ~= nil,
			`PetCatalogue: Config.Eggs.Available has unknown egg {tostring(egg)}`
		)
		assert(type(entry.Name) == "string" and entry.Name ~= "", `PetCatalogue: egg {egg} needs a Name`)
		-- Every rarity the egg can roll (Config.Pets.Odds) needs its pet, or a hatch would have no
		-- result. Checked here, not at hatch time.
		for rarity, chance in pets.Odds do
			if chance > 0 then
				assert(
					byEgg[egg] ~= nil and byEgg[egg][rarity] ~= nil,
					`PetCatalogue: egg {egg} is available but has no {rarity} pet`
				)
			end
		end
		available[egg] = true
	end

	local zoneEgg: { [number]: number } = {}
	for egg, zone in pets.EggZones do
		zoneEgg[zone] = egg
	end

	local function get(kind: string): PetInfo?
		if type(kind) ~= "string" then
			return nil
		end
		return infos[kind]
	end

	local function petsOf(egg: number): { PetInfo }
		local list = {}
		for _, id in ids do
			if infos[id].egg == egg then
				table.insert(list, infos[id])
			end
		end
		return list
	end

	local function bonusOf(record: any): number?
		if type(record) ~= "table" then
			return nil
		end
		local info = get(record.kind)
		if info == nil then
			return nil
		end
		local variant = record.variant
		if variant ~= nil and (type(variant) ~= "string" or pets.VariantMultipliers[variant] == nil) then
			return nil
		end
		local frosty = record.frosty
		if frosty ~= nil and type(frosty) ~= "boolean" then
			return nil
		end
		return petBonus({ egg = info.egg, rarity = info.rarity, variant = variant, frosty = frosty })
	end

	local function multiplierText(value: number, decimals: number): string
		local text = string.format(`%.{decimals}f`, value)
		if string.find(text, ".", 1, true) then
			text = string.gsub(text, "0+$", "")
			text = string.gsub(text, "%.$", "")
		end
		return text
	end

	return table.freeze({
		ids = table.freeze(ids),
		isKind = function(kind: any): boolean
			return type(kind) == "string" and infos[kind] ~= nil
		end,
		get = get,
		petFor = function(egg: number, rarity: string): string?
			local slot = byEgg[egg]
			return if slot then slot[rarity] else nil
		end,
		petsOf = petsOf,
		isAvailable = function(egg: any): boolean
			return isWhole(egg) and available[egg] == true
		end,
		eggName = function(egg: number): string?
			local entry = eggs.Available[egg]
			return if entry then entry.Name else nil
		end,
		eggForZone = function(zone: any): number?
			if not isWhole(zone) then
				return nil
			end
			return zoneEgg[zone]
		end,
		bonusOf = bonusOf,
		multiplierText = multiplierText,
	})
end

return table.freeze(Catalogue)

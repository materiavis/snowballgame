--!strict
-- Egg and find chance tables and rolls (concept 7.7, 7.9, 8.5). Pure: config, zone formulas,
-- the Weighted picker and the generator are passed in; Rng/init.luau binds them in Roblox.
--
-- A table lists every possible outcome with its chance in percent, secret included, so the
-- egg station and the collection book can show exactly what the roll uses (8.5: chances are
-- always visible). The secret chance comes off every other rarity in proportion, which is the
-- same as "roll the secret first, otherwise roll the rarity table".

export type Entry = { id: string, weight: number }
export type Generator = { next: () -> number } -- uniform in [0, 1)

type Picker = { pick: (entries: { Entry }, roll: number) -> string }
type ZoneValues = { zoneInWorld: (zone: number) -> number, isZone: (zone: any) -> boolean }

export type OddsConfig = {
	order: { string }, -- Config.Rarity.Order, lowest first
	pets: {
		EggZones: { number },
		Odds: { [string]: number },
		LuckOdds: { [string]: number },
		SecretPetChance: number,
		SecretPetFromEgg: number,
		FrostyChance: number,
	},
	finds: {
		Odds: { [string]: number },
		LegendaryFromZoneInWorld: number,
		LegendaryFallback: string,
		SecretChance: number,
	},
}

export type Hatch = { rarity: string, frosty: boolean }

export type Odds = {
	eggOdds: (egg: number, luck: boolean) -> { Entry },
	findOdds: (zone: number) -> { Entry },
	rollEgg: (egg: number, luck: boolean, generator: Generator) -> Hatch,
	rollFind: (zone: number, generator: Generator) -> string,
}

local SECRET = "Secret"

local Odds = {}

function Odds.new(config: OddsConfig, zones: ZoneValues, picker: Picker): Odds
	-- Base percentages in rarity order, then the secret share taken off in proportion.
	local function build(base: { [string]: number }, secretChance: number): { Entry }
		local entries: { Entry } = {}
		for _, id in config.order do
			local weight = base[id]
			if id ~= SECRET and weight ~= nil then
				table.insert(entries, { id = id, weight = weight * (1 - secretChance) })
			end
		end
		if secretChance > 0 then
			table.insert(entries, { id = SECRET, weight = secretChance * 100 })
		end
		return entries
	end

	local function checkEgg(egg: number)
		if type(egg) ~= "number" or config.pets.EggZones[egg] == nil then
			error(`Rng.Odds: egg must be 1..{#config.pets.EggZones}, got {tostring(egg)}`, 3)
		end
	end

	local function eggOdds(egg: number, luck: boolean): { Entry }
		checkEgg(egg)
		local base = if luck then config.pets.LuckOdds else config.pets.Odds
		local secret = if egg >= config.pets.SecretPetFromEgg then config.pets.SecretPetChance else 0
		return build(base, secret)
	end

	-- Zones 1 to 5 of each world have no Legendary finds; that chance goes to the fallback.
	local function findOdds(zone: number): { Entry }
		if not zones.isZone(zone) then
			error(`Rng.Odds: unknown zone {tostring(zone)}`, 2)
		end
		local base = table.clone(config.finds.Odds)
		if zones.zoneInWorld(zone) < config.finds.LegendaryFromZoneInWorld then
			local fallback = config.finds.LegendaryFallback
			base[fallback] = (base[fallback] or 0) + (base.Legendary or 0)
			base.Legendary = nil
		end
		return build(base, config.finds.SecretChance)
	end

	-- One roll picks the rarity (secret included); a second, independent roll decides Frosty.
	local function rollEgg(egg: number, luck: boolean, generator: Generator): Hatch
		local rarity = picker.pick(eggOdds(egg, luck), generator.next())
		local frosty = generator.next() < config.pets.FrostyChance
		return { rarity = rarity, frosty = frosty }
	end

	local function rollFind(zone: number, generator: Generator): string
		return picker.pick(findOdds(zone), generator.next())
	end

	return table.freeze({
		eggOdds = eggOdds,
		findOdds = findOdds,
		rollEgg = rollEgg,
		rollFind = rollFind,
	})
end

return table.freeze(Odds)

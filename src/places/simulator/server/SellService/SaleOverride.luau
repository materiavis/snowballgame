--!strict
-- Sale bonus flags and the Studio switch SellFactorOverride (ADR 0012). Pure.
--
-- The flag names are the keys of Config.Economy.SellMultipliedBonuses and SellAddedBonuses
-- (Double coins, Coins boost, Golden snow; VIP, Premium; concept 8.3).
--
-- Override text: space-separated `key=value` pairs, each key at most once.
--   pet=<number >= 1>              replaces the PetMultiplier attribute
--   rebirths=<whole number 0..MAX> replaces sim.rebirths (only for the sale, the profile stays)
--   bonus=<Flag>[,<Flag>...]       these flags on, every other one off; bonus=none: all off
-- An empty text means no override.

export type Flags = { [string]: boolean }

export type Override = {
	pet: number?,
	rebirths: number?,
	flags: Flags?,
}

local MAX_REBIRTHS = 1e6

local SaleOverride = {}

-- Every known flag name, sorted, from the economy config's bonus tables.
function SaleOverride.flagNames(economy: any): { string }
	local names = {}
	for name in economy.SellMultipliedBonuses do
		table.insert(names, name)
	end
	for name in economy.SellAddedBonuses do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Every known flag, off.
function SaleOverride.noFlags(names: { string }): Flags
	local flags: Flags = {}
	for _, name in names do
		flags[name] = false
	end
	return flags
end

-- The active flags as text, e.g. "DoubleCoins,Vip" ("" when none is on).
function SaleOverride.describeFlags(flags: Flags): string
	local on = {}
	for name, active in flags do
		if active then
			table.insert(on, name)
		end
	end
	table.sort(on)
	return table.concat(on, ",")
end

local function parseNumber(text: string): number?
	local value = tonumber(text)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

-- Returns the override (nil for an empty text) or nil and the problem.
function SaleOverride.parse(text: any, names: { string }): (Override?, string?)
	if type(text) ~= "string" then
		return nil, "expected a string"
	end
	local override: Override = {}
	local seen: { [string]: boolean } = {}
	local any = false
	for pair in string.gmatch(text, "%S+") do
		local key, value = string.match(pair, "^(%a+)=(%S+)$")
		if key == nil or value == nil then
			return nil, `expected key=value, got {pair}`
		end
		if seen[key] then
			return nil, `{key} given twice`
		end
		seen[key] = true
		any = true
		if key == "pet" then
			local number = parseNumber(value)
			if number == nil or number < 1 then
				return nil, `pet must be a number >= 1, got {value}`
			end
			override.pet = number
		elseif key == "rebirths" then
			local number = parseNumber(value)
			if number == nil or number < 0 or number % 1 ~= 0 or number > MAX_REBIRTHS then
				return nil, `rebirths must be a whole number 0..{MAX_REBIRTHS}, got {value}`
			end
			override.rebirths = number
		elseif key == "bonus" then
			local flags = SaleOverride.noFlags(names)
			if value ~= "none" then
				for name in string.gmatch(value, "[^,]+") do
					if flags[name] == nil then
						return nil, `unknown bonus {name} (known: {table.concat(names, ",")})`
					end
					flags[name] = true
				end
			end
			override.flags = flags
		else
			return nil, `unknown key {key} (pet, rebirths, bonus)`
		end
	end
	if not any then
		return nil, nil
	end
	return override, nil
end

return table.freeze(SaleOverride)

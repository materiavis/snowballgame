--!strict
-- Argument validators for remote schemas. Pure (no services, no Instances at require time),
-- so the headless tests under Lune load it directly.
--
-- Every bounded type demands its bounds when it is declared: a number without min/max or a
-- string without maxLength errors at startup, because "any number" from a client is exactly
-- the value CLAUDE.md §6 says never to trust.

export type Validator = {
	check: (value: any) -> (boolean, string?),
	optional: boolean,
	describe: string,
}

-- A property of UTF-8, not a tuning value: no character takes more bytes than this.
local MAX_UTF8_BYTES_PER_CHAR = 4

local Schema = {}

local function validator(describe: string, check: (value: any) -> (boolean, string?)): Validator
	return table.freeze({ check = check, optional = false, describe = describe })
end

local function isFiniteNumber(value: any): boolean
	-- NaN fails every comparison, so value == value is the NaN test; huge values fail the bound.
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function requireBound(owner: string, field: string, value: any)
	if not isFiniteNumber(value) then
		error(`Net.Schema.{owner}: '{field}' must be a finite number, got {tostring(value)}`, 3)
	end
end

local function requireLength(owner: string, field: string, value: any)
	if not isFiniteNumber(value) or value < 0 or value % 1 ~= 0 then
		error(`Net.Schema.{owner}: '{field}' must be a whole number >= 0, got {tostring(value)}`, 3)
	end
end

local function typeName(value: any): string
	return typeof(value)
end

function Schema.boolean(): Validator
	return validator("boolean", function(value)
		if type(value) ~= "boolean" then
			return false, `expected boolean, got {typeName(value)}`
		end
		return true
	end)
end

export type NumberOptions = { min: number, max: number, integer: boolean? }

function Schema.number(options: NumberOptions): Validator
	requireBound("number", "min", options.min)
	requireBound("number", "max", options.max)
	if options.min > options.max then
		error(`Net.Schema.number: min {options.min} is greater than max {options.max}`, 2)
	end
	local min, max, integer = options.min, options.max, options.integer == true
	return validator(`number[{min}, {max}]`, function(value)
		if type(value) ~= "number" then
			return false, `expected number, got {typeName(value)}`
		end
		if not isFiniteNumber(value) then
			return false, "number is NaN or infinite"
		end
		if integer and value % 1 ~= 0 then
			return false, "expected a whole number"
		end
		if value < min or value > max then
			return false, `number {value} is outside [{min}, {max}]`
		end
		return true
	end)
end

export type StringOptions = { maxLength: number, minLength: number? }

function Schema.string(options: StringOptions): Validator
	requireLength("string", "maxLength", options.maxLength)
	local minLength = options.minLength or 0
	requireLength("string", "minLength", minLength)
	local maxLength = options.maxLength
	return validator(`string[{minLength}..{maxLength}]`, function(value)
		if type(value) ~= "string" then
			return false, `expected string, got {typeName(value)}`
		end
		-- Byte length first, so a huge payload is refused before utf8.len walks it.
		if #value > maxLength * MAX_UTF8_BYTES_PER_CHAR then
			return false, "string is too long"
		end
		local length = utf8.len(value)
		if length == nil then
			return false, "string is not valid UTF-8"
		end
		if length < minLength or length > maxLength then
			return false, `string length {length} is outside [{minLength}, {maxLength}]`
		end
		return true
	end)
end

-- A closed set of string values, e.g. a menu tab or an upgrade id.
function Schema.enum(values: { string }): Validator
	if type(values) ~= "table" or #values == 0 then
		error("Net.Schema.enum: needs a non-empty list of strings", 2)
	end
	local allowed: { [string]: true } = {}
	for _, entry in values do
		if type(entry) ~= "string" then
			error("Net.Schema.enum: every value must be a string", 2)
		end
		allowed[entry] = true
	end
	return validator(`enum({table.concat(values, "|")})`, function(value)
		if type(value) ~= "string" or not allowed[value] then
			return false, "value is not one of the allowed options"
		end
		return true
	end)
end

export type VectorOptions = { maxMagnitude: number }

-- For directions and aim vectors. Positions are better checked by an authorize hook
-- against the server's own view of the world.
function Schema.vector3(options: VectorOptions): Validator
	requireBound("vector3", "maxMagnitude", options.maxMagnitude)
	local maxMagnitude = options.maxMagnitude
	return validator(`Vector3(|v| <= {maxMagnitude})`, function(value)
		if typeof(value) ~= "Vector3" then
			return false, `expected Vector3, got {typeName(value)}`
		end
		if not (isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)) then
			return false, "Vector3 has a NaN or infinite component"
		end
		if value.Magnitude > maxMagnitude then
			return false, "Vector3 is too long"
		end
		return true
	end)
end

-- Only checks the class. Whether the player may act on this Instance (ownership,
-- distance, line of sight) belongs in the remote's authorize hook.
function Schema.instance(className: string): Validator
	if type(className) ~= "string" or className == "" then
		error("Net.Schema.instance: needs a class name", 2)
	end
	return validator(`Instance({className})`, function(value)
		if typeof(value) ~= "Instance" then
			return false, `expected Instance, got {typeName(value)}`
		end
		if not value:IsA(className) then
			return false, `expected a {className}`
		end
		return true
	end)
end

export type ArrayOptions = { maxLength: number }

function Schema.array(element: Validator, options: ArrayOptions): Validator
	if type(element) ~= "table" or type(element.check) ~= "function" then
		error("Net.Schema.array: element must be a Schema validator", 2)
	end
	requireLength("array", "maxLength", options.maxLength)
	local maxLength = options.maxLength
	return validator(`array<{element.describe}>[{maxLength}]`, function(value)
		if type(value) ~= "table" then
			return false, `expected table, got {typeName(value)}`
		end
		-- Count keys without trusting #, which is undefined for tables with holes.
		local count = 0
		for key in value do
			count += 1
			if count > maxLength then
				return false, `array has more than {maxLength} entries`
			end
			if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
				return false, "array has a non-index key"
			end
		end
		for index = 1, count do
			local entry = value[index]
			if entry == nil then
				return false, "array has holes"
			end
			local ok, reason = element.check(entry)
			if not ok then
				return false, `[{index}] {reason}`
			end
		end
		return true
	end)
end

-- A table with exactly these fields. Unknown keys are refused, so clients cannot smuggle
-- extra data past a handler that later iterates the table.
function Schema.struct(fields: { [string]: Validator }): Validator
	if type(fields) ~= "table" or next(fields) == nil then
		error("Net.Schema.struct: needs at least one field", 2)
	end
	local names: { string } = {}
	for name, field in fields do
		if type(name) ~= "string" or type(field) ~= "table" or type(field.check) ~= "function" then
			error("Net.Schema.struct: fields must map names to Schema validators", 2)
		end
		table.insert(names, name)
	end
	table.sort(names)
	return validator("struct(" .. table.concat(names, ", ") .. ")", function(value)
		if type(value) ~= "table" then
			return false, `expected table, got {typeName(value)}`
		end
		for key in value do
			if type(key) ~= "string" or fields[key] == nil then
				return false, "struct has an unknown key"
			end
		end
		for _, name in names do
			local field = fields[name]
			local entry = value[name]
			if entry == nil then
				if not field.optional then
					return false, `field '{name}' is missing`
				end
			else
				local ok, reason = field.check(entry)
				if not ok then
					return false, `field '{name}': {reason}`
				end
			end
		end
		return true
	end)
end

-- nil is accepted; any other value must pass the inner validator. As a remote argument,
-- optional ones may only come after all required ones (checked by Registry).
function Schema.optional(inner: Validator): Validator
	if type(inner) ~= "table" or type(inner.check) ~= "function" then
		error("Net.Schema.optional: needs a Schema validator", 2)
	end
	local innerCheck = inner.check
	return table.freeze({
		check = function(value: any): (boolean, string?)
			if value == nil then
				return true
			end
			return innerCheck(value)
		end,
		optional = true,
		describe = `{inner.describe}?`,
	})
end

return table.freeze(Schema)

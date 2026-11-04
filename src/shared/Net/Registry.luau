--!strict
-- Checks remote declarations once, at startup, and turns them into frozen definitions.
-- Pure, so the "a remote without a schema fails loudly" rule is proven headless.
--
-- Anything wrong is an error rather than a default: a remote that silently fell back to
-- "no schema" or "no rate limit" would be an unvalidated door into the server.

export type Validator = {
	check: (value: any) -> (boolean, string?),
	optional: boolean,
	describe: string,
}

export type Limit = { Burst: number, RefillPerSecond: number }

export type Kind = "Event" | "Function"

-- Runs after the argument types passed. Ownership, distance, cooldowns and other checks that
-- need game state go here. Returning false (or throwing) drops the call.
export type Authorize = (player: any, ...any) -> (boolean, string?)

export type Declaration = {
	kind: Kind,
	args: { Validator },
	rateLimit: Limit,
	authorize: Authorize?,
}

export type Definition = {
	name: string,
	kind: Kind,
	args: { Validator },
	rateLimit: Limit,
	authorize: Authorize?,
	minArgs: number,
	maxArgs: number,
}

local KNOWN_FIELDS = { kind = true, args = true, rateLimit = true, authorize = true }

local Registry = {}

local function fail(name: string, message: string): never
	error(`Net: remote '{name}' {message}`, 0)
end

local function isPositiveFinite(value: any): boolean
	return type(value) == "number" and value > 0 and value ~= math.huge
end

local function isValidator(value: any): boolean
	return type(value) == "table"
		and type(value.check) == "function"
		and type(value.optional) == "boolean"
		and type(value.describe) == "string"
end

local function checkLimit(name: string, limit: any)
	if type(limit) ~= "table" then
		fail(name, "has no rateLimit (every remote needs a per-player rate limit from Config.Net)")
	end
	if not isPositiveFinite(limit.Burst) or limit.Burst % 1 ~= 0 then
		fail(name, `rateLimit.Burst must be a whole number > 0, got {tostring(limit.Burst)}`)
	end
	if not isPositiveFinite(limit.RefillPerSecond) then
		fail(name, `rateLimit.RefillPerSecond must be a number > 0, got {tostring(limit.RefillPerSecond)}`)
	end
end

function Registry.buildOne(name: string, declaration: any): Definition
	if type(name) ~= "string" or not string.match(name, "^%a[%w_]*$") then
		error(`Net: remote name must be an identifier-like string, got {tostring(name)}`, 0)
	end
	if type(declaration) ~= "table" then
		fail(name, "must be declared as a table")
	end
	for field in declaration do
		if not KNOWN_FIELDS[field] then
			-- Catches typos such as `schema =` instead of `args =`.
			fail(name, `has unknown field '{tostring(field)}'`)
		end
	end
	if declaration.kind ~= "Event" and declaration.kind ~= "Function" then
		fail(name, `kind must be "Event" or "Function", got {tostring(declaration.kind)}`)
	end

	local args = declaration.args
	if type(args) ~= "table" then
		fail(name, "has no args schema (declare `args = {}` for a remote without arguments)")
	end
	local count = 0
	for _ in args do
		count += 1
	end
	if count ~= #args then
		fail(name, "args must be a list of Schema validators")
	end
	local minArgs = 0
	for index = 1, #args do
		local validator = args[index]
		if not isValidator(validator) then
			fail(name, `args[{index}] is not a Schema validator`)
		end
		if validator.optional then
			continue
		end
		if minArgs ~= index - 1 then
			fail(name, `args[{index}] is required but follows an optional argument`)
		end
		minArgs = index
	end

	checkLimit(name, declaration.rateLimit)
	if declaration.authorize ~= nil and type(declaration.authorize) ~= "function" then
		fail(name, "authorize must be a function")
	end

	return table.freeze({
		name = name,
		kind = declaration.kind,
		args = table.freeze(table.clone(args)),
		rateLimit = declaration.rateLimit,
		authorize = declaration.authorize,
		minArgs = minArgs,
		maxArgs = #args,
	})
end

function Registry.build(declarations: { [string]: any }): { [string]: Definition }
	if type(declarations) ~= "table" then
		error("Net: remote declarations must be a table keyed by remote name", 0)
	end
	local definitions: { [string]: Definition } = {}
	for name, declaration in declarations do
		definitions[name] = Registry.buildOne(name, declaration)
	end
	return table.freeze(definitions)
end

return table.freeze(Registry)

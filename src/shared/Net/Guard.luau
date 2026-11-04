--!strict
-- Wraps a remote handler in the checks every client call must pass, in this order:
-- rate, argument count, argument types and ranges, authorize hook, then the handler.
-- Pure: the limiter, the counters and the handler lookup are passed in.
--
-- Rate comes first so a flood of malformed calls is capped as cheaply as possible.
-- Nothing here may throw: a rejected call returns no values (a RemoteFunction caller gets
-- nil) and is counted. Validator, authorize and handler errors are caught for the same reason.

type Validator = {
	check: (value: any) -> (boolean, string?),
	optional: boolean,
	describe: string,
}

type Definition = {
	name: string,
	args: { Validator },
	authorize: ((player: any, ...any) -> (boolean, string?))?,
	minArgs: number,
	maxArgs: number,
}

type Limiter = { take: (self: any, key: any) -> boolean }

type Counter = {
	accepted: (self: any, remote: string, player: any) -> (),
	rejected: (self: any, remote: string, reason: any, detail: string, player: any) -> (),
	handlerError: (self: any, remote: string, detail: string, player: any) -> (),
}

export type Handler = (player: any, ...any) -> ...any

export type Deps = {
	limiter: Limiter,
	stats: Counter,
	getHandler: () -> Handler?,
	-- Server-side logging of a handler error. Never reaches the client.
	reportError: (remote: string, message: string) -> (),
}

local Guard = {}

function Guard.new(definition: Definition, deps: Deps): (player: any, ...any) -> ...any
	local name = definition.name
	local args = definition.args
	local minArgs, maxArgs = definition.minArgs, definition.maxArgs
	local authorize = definition.authorize

	return function(player: any, ...: any): ...any
		if not deps.limiter:take(player) then
			deps.stats:rejected(name, "Rate", "over the rate limit", player)
			return
		end

		local values = table.pack(...)
		if values.n < minArgs or values.n > maxArgs then
			deps.stats:rejected(name, "Arity", `expected {minArgs}..{maxArgs} arguments, got {values.n}`, player)
			return
		end

		for index = 1, maxArgs do
			local validator = args[index]
			local value = values[index]
			if value == nil then
				if not validator.optional then
					deps.stats:rejected(name, "Args", `argument {index} is missing`, player)
					return
				end
			else
				local ran, ok, reason = pcall(validator.check, value)
				if not ran or not ok then
					local detail = if ran then reason or "invalid" else "validator error"
					deps.stats:rejected(name, "Args", `argument {index}: {detail}`, player)
					return
				end
			end
		end

		if authorize then
			local ran, ok, reason = pcall(authorize, player, table.unpack(values, 1, values.n))
			if not ran or ok ~= true then
				local detail = if ran then reason or "not allowed" else "authorize error"
				deps.stats:rejected(name, "Auth", detail, player)
				return
			end
		end

		local handler = deps.getHandler()
		if handler == nil then
			deps.stats:rejected(name, "NoHandler", "no handler is registered", player)
			return
		end

		local results = table.pack(pcall(handler, player, table.unpack(values, 1, values.n)))
		if not results[1] then
			local message = tostring(results[2])
			deps.stats:handlerError(name, message, player)
			pcall(deps.reportError, name, message)
			return
		end
		deps.stats:accepted(name, player)
		return table.unpack(results, 2, results.n)
	end
end

return table.freeze(Guard)

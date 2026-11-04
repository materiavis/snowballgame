--!strict
-- Declaring a remote without a schema or rate limit fails loudly; the real declarations in
-- src/shared/Net/Remotes all pass. Limits in the hand-made declarations are test values.

local T = require("../../TestKit")
local Schema = require("../../../src/shared/Net/Schema")
local Registry = require("../../../src/shared/Net/Registry")
local declareRemotes = require("../../../src/shared/Net/Remotes")
local NetConfig = require("../../../src/shared/Config/Net")

local LIMIT = { Burst = 1, RefillPerSecond = 1 }

local function build(declaration: any)
	return Registry.build({ TestRemote = declaration })
end

return T.suite("src/shared/Net/Registry", function(test)
	test("every real remote has a schema, a rate limit from Config.Net and a valid kind", function()
		local definitions = Registry.build(declareRemotes(Schema, NetConfig))
		local count = 0
		for name, definition in definitions do
			count += 1
			T.equal(type(definition.args), "table", `{name} args`)
			T.isTrue(NetConfig.RateLimits[name] ~= nil, `{name} has a Config.Net.RateLimits entry`)
			T.equal(definition.rateLimit, NetConfig.RateLimits[name], `{name} uses its own Config.Net limit`)
		end
		T.isTrue(count >= 1, "at least the example remote is declared")
		T.isTrue(table.isfrozen(definitions), "definitions are frozen")
	end)

	test("a remote without a schema fails loudly", function()
		T.throws(function()
			build({ kind = "Event", rateLimit = LIMIT })
		end, "no args schema")
	end)

	test("a typo for the schema field fails loudly", function()
		T.throws(function()
			build({ kind = "Event", schema = {}, rateLimit = LIMIT })
		end, "unknown field 'schema'")
	end)

	test("a remote without a rate limit fails loudly", function()
		T.throws(function()
			build({ kind = "Event", args = {} })
		end, "no rateLimit")
		T.throws(function()
			build({ kind = "Event", args = {}, rateLimit = { Burst = 0, RefillPerSecond = 1 } })
		end, "Burst")
		T.throws(function()
			build({ kind = "Event", args = {}, rateLimit = { Burst = 1, RefillPerSecond = 0 / 0 } })
		end, "RefillPerSecond")
	end)

	test("args must be Schema validators in a list, optional ones last", function()
		T.throws(function()
			build({ kind = "Event", args = { "number" }, rateLimit = LIMIT })
		end, "not a Schema validator")
		T.throws(function()
			build({ kind = "Event", args = { x = Schema.boolean() }, rateLimit = LIMIT })
		end, "list")
		T.throws(function()
			build({
				kind = "Event",
				args = { Schema.optional(Schema.boolean()), Schema.boolean() },
				rateLimit = LIMIT,
			})
		end, "follows an optional")
	end)

	test("kind, name and authorize are checked", function()
		T.throws(function()
			build({ kind = "Remote", args = {}, rateLimit = LIMIT })
		end, "kind")
		T.throws(function()
			Registry.build({ ["bad name"] = { kind = "Event", args = {}, rateLimit = LIMIT } })
		end, "name")
		T.throws(function()
			build({ kind = "Event", args = {}, rateLimit = LIMIT, authorize = true })
		end, "authorize")
	end)

	test("argument counts come from required and optional args", function()
		local definitions = build({
			kind = "Function",
			args = { Schema.boolean(), Schema.optional(Schema.boolean()) },
			rateLimit = LIMIT,
		})
		T.equal(definitions.TestRemote.minArgs, 1)
		T.equal(definitions.TestRemote.maxArgs, 2)
	end)
end)

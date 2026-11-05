--!strict
-- Exponential backoff with an injected wait; the settings are test values.

local T = require("../../TestKit")
local Retry = require("../../../src/server/Services/DataService/Retry")

local SETTINGS = { StoreAttempts = 5, BackoffBase = 1, BackoffFactor = 2, BackoffMax = 4 }

return T.suite("DataService/Retry", function(test)
	test("backs off exponentially up to the cap", function()
		local waits: { number } = {}
		local retry = Retry.new(SETTINGS, function(seconds)
			table.insert(waits, seconds)
		end)
		local ok, err = retry.run(function()
			error("down", 0)
		end)
		T.equal(ok, false)
		T.equal(err, "down")
		T.equal(#waits, 4, "no wait after the last attempt")
		T.equal(waits[1], 1)
		T.equal(waits[2], 2)
		T.equal(waits[3], 4)
		T.equal(waits[4], 4, "capped")
	end)

	test("returns the result once a call succeeds", function()
		local calls = 0
		local retry = Retry.new(SETTINGS, function() end)
		local ok, value = retry.run(function()
			calls += 1
			if calls < 3 then
				error("busy")
			end
			return "done"
		end)
		T.equal(ok, true)
		T.equal(value, "done")
		T.equal(calls, 3)
	end)
end)

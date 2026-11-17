--!strict
-- Config.Travel holds every travel number (issue #28 AC5) and they make sense together.

local T = require("../TestKit")
local Travel = require("../../src/shared/Config/Travel")

local function positive(value: any): boolean
	return type(value) == "number" and value > 0 and value < math.huge
end

local function whole(value: any): boolean
	return positive(value) and value % 1 == 0
end

return T.suite("src/shared/Config/Travel", function(test)
	test("frozen, attempts are whole and times positive", function()
		T.isTrue(table.isfrozen(Travel) and table.isfrozen(Travel.Messages))
		for _, name in
			{
				"SaveAttempts",
				"TeleportAttempts",
				"ResumeAttempts",
				"LoadFailuresBeforeLobby",
				"PresenceAttempts",
				"FriendLookupMax",
			}
		do
			T.isTrue(whole(Travel[name]), name)
		end
		for _, name in
			{
				"SaveRetryDelay",
				"TeleportRetryBase",
				"TeleportRetryFactor",
				"TeleportRetryMax",
				"TeleportTimeout",
				"TeleportPoll",
				"ResumeRetryDelay",
				"LoadFailReturnDelay",
				"PresenceTtl",
				"PresenceRefresh",
				"PrivateMappingTtl",
				"PresenceRetryDelay",
				"MessageSeconds",
			}
		do
			T.isTrue(positive(Travel[name]), name)
		end
	end)

	test("ADR 0003: presence TTL 60 s, refreshed at most every 30 s", function()
		T.equal(Travel.PresenceTtl, 60)
		T.isTrue(Travel.PresenceRefresh <= 30)
		T.isTrue(Travel.PrivateMappingTtl <= 45 * 24 * 3600, "MemoryStore maximum")
	end)

	test("every message is a short non-empty text", function()
		for key, text in Travel.Messages do
			T.isTrue(type(text) == "string" and #text > 0 and utf8.len(text) ~= nil, key)
			T.isTrue((utf8.len(text) :: number) <= 60, `{key} is short`)
		end
	end)
end)

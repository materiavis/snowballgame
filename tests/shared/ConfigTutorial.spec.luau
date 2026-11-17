--!strict
-- Config.Tutorial (#42 AC7, ADR 0017): one consistent list of hint ids, so the server rules, the
-- remote's enum and the client never disagree. Structural checks, not tuning values.

local T = require("../TestKit")
local Tutorial = require("../../src/shared/Config/Tutorial")
local TutorialAttributes = require("../../src/shared/TutorialAttributes")

local PLACES = { Lobby = true, Simulator = true }
local CHANNELS = { Controls = true, World = true, Screen = true, Pulse = true }

return T.suite("Config.Tutorial", function(test)
	test("every hint in Order has an entry, a known Place and Channel, and is frozen", function()
		T.isTrue(table.isfrozen(Tutorial), "frozen")
		local seen = {}
		for index, id in Tutorial.Order do
			T.equal(seen[id], nil, `{id} listed once`)
			seen[id] = index
			local hint = Tutorial.Hints[id]
			T.isTrue(hint ~= nil, `{id} has a Hints entry`)
			T.isTrue(PLACES[hint.Place] == true, `{id} Place`)
			T.isTrue(CHANNELS[hint.Channel] == true, `{id} Channel`)
			T.isTrue(string.find(id, ",", 1, true) == nil, `{id} has no comma (attribute list format)`)
		end
		for id in Tutorial.Hints do
			T.isTrue(seen[id] ~= nil, `{id} is in Order`)
		end
	end)

	test("Requires only names earlier hints of the same Place", function()
		local index = {}
		for i, id in Tutorial.Order do
			index[id] = i
		end
		for id, hint in Tutorial.Hints do
			for _, required in hint.Requires do
				T.isTrue(index[required] ~= nil and index[required] < index[id], `{id} requires earlier {required}`)
				T.equal(Tutorial.Hints[required].Place, hint.Place, `{id} requires a hint of its Place`)
			end
		end
	end)

	test("client-reportable ids and the multi-arrow id are hints", function()
		T.isTrue(#Tutorial.ClientReportable > 0)
		for _, id in Tutorial.ClientReportable do
			T.isTrue(Tutorial.Hints[id] ~= nil, id)
		end
		T.equal(Tutorial.Hints[Tutorial.MultiArrowHint].Place, "Lobby")
	end)

	test("the numbers are positive and the stand-in offsets have three components", function()
		for _, name in
			{ "CheckInterval", "MoveDoneDistance", "MaxStepPerCheck", "EggReachDistance", "BarrierReachDistance" }
		do
			local value = (Tutorial :: any)[name]
			T.isTrue(type(value) == "number" and value > 0, name)
		end
		T.isTrue(Tutorial.MaxStepPerCheck > Tutorial.MoveDoneDistance / 2, "a normal step always counts")
		T.equal(#Tutorial.Test.EggOffset, 3)
		T.equal(#Tutorial.Test.BarrierOffset, 3)
	end)

	test("TutorialAttributes list format round-trips and ignores junk", function()
		T.equal(TutorialAttributes.encode({ "A", "B" }), "A,B")
		T.equal(TutorialAttributes.encode({}), "")
		T.equal(table.concat(TutorialAttributes.decode("A,B"), "|"), "A|B")
		T.equal(#TutorialAttributes.decode(""), 0)
		T.equal(#TutorialAttributes.decode(nil), 0)
		T.equal(#TutorialAttributes.decode(5), 0)
		T.equal(table.concat(TutorialAttributes.decode("A,,B"), "|"), "A|B")
		T.isTrue(TutorialAttributes.has("ZoneMove,MaxScale", "MaxScale"))
		T.equal(TutorialAttributes.has("ZoneMove,MaxScale", "Max"), false)
		T.equal(TutorialAttributes.has(nil, "MaxScale"), false)
	end)
end)

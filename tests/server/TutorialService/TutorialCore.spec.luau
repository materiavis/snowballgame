--!strict
-- The onboarding rules (#42 AC3, AC6; ADR 0017): every hint once, in order, gone after its action;
-- a client report only for a reportable hint that is showing; nothing ever set back to unseen.

local T = require("../../TestKit")
local TutorialConfig = require("../../../src/shared/Config/Tutorial")
local TutorialCore = require("../../../src/server/Services/TutorialService/TutorialCore")

local core = TutorialCore.new(TutorialConfig :: any)

local function fresh(): any
	return { seenSingleArrow = false, seenMultiArrow = false, hints = {}, firstMatchHints = false }
end

local function all(ids: { string }): { [string]: boolean }
	local out = {}
	for _, id in ids do
		out[id] = true
	end
	return out
end

local SIM_ALL = all({ "ZoneMove", "MaxScale", "UpgradesButton", "EggStation", "BarrierPulse" })

return T.suite("TutorialService rules", function(test)
	test("AC3: a new Lobby player sees the controls hint first; the Multiplayer arrow waits for it", function()
		local tutorial = fresh()
		local showing, active = core.select("Lobby", tutorial, all({ "LobbyMove", "LobbyMultiArrow" }), {})
		T.equal(table.concat(active, ","), "LobbyMove")
		T.isTrue(core.markDone(tutorial, "LobbyMove"))
		showing, active = core.select("Lobby", tutorial, all({ "LobbyMove", "LobbyMultiArrow" }), showing)
		T.equal(table.concat(active, ","), "LobbyMultiArrow")
		T.isTrue(core.markDone(tutorial, "LobbyMultiArrow"))
		T.equal(tutorial.seenMultiArrow, true, "the Multiplayer arrow is the schema v1 flag")
		T.equal(tutorial.hints.LobbyMultiArrow, nil, "and not a hints entry")
		_, active = core.select("Lobby", tutorial, all({ "LobbyMove", "LobbyMultiArrow" }), showing)
		T.equal(#active, 0, "both done: nothing shows again")
	end)

	test("AC3: the Simulator timeline in order, one hint per channel", function()
		local tutorial = fresh()
		local showing, active = core.select("Simulator", tutorial, SIM_ALL, {})
		T.equal(table.concat(active, ","), "ZoneMove", "the controls first, everything else requires them")
		core.markDone(tutorial, "ZoneMove")
		showing, active = core.select("Simulator", tutorial, SIM_ALL, showing)
		T.equal(
			table.concat(active, ","),
			"MaxScale,BarrierPulse",
			"World and Pulse channels; Upgrades waits for a sale"
		)
		core.markDone(tutorial, "MaxScale") -- the first sale
		showing, active = core.select("Simulator", tutorial, SIM_ALL, showing)
		T.equal(table.concat(active, ","), "UpgradesButton,EggStation,BarrierPulse")
		core.markDone(tutorial, "UpgradesButton")
		core.markDone(tutorial, "EggStation")
		core.markDone(tutorial, "BarrierPulse")
		_, active = core.select("Simulator", tutorial, SIM_ALL, showing)
		T.equal(#active, 0)
		T.equal(table.concat(core.doneList(tutorial), ","), "ZoneMove,MaxScale,UpgradesButton,EggStation,BarrierPulse")
	end)

	test("AC3: a showing hint keeps its channel until done, so it never appears twice", function()
		local tutorial = fresh()
		core.markDone(tutorial, "ZoneMove")
		-- Coins for the egg first (e.g. from the group chest): the egg arrow takes the World channel.
		local showing, active = core.select("Simulator", tutorial, all({ "EggStation" }), {})
		T.equal(table.concat(active, ","), "EggStation")
		-- Then MAX: the earlier MaxScale does not take the channel away.
		showing, active = core.select("Simulator", tutorial, all({ "MaxScale", "EggStation" }), showing)
		T.equal(table.concat(active, ","), "EggStation")
		-- Coins spent: the egg arrow stays until its action.
		showing, active = core.select("Simulator", tutorial, all({ "MaxScale" }), showing)
		T.equal(table.concat(active, ","), "EggStation")
		core.markDone(tutorial, "EggStation")
		_, active = core.select("Simulator", tutorial, all({ "MaxScale" }), showing)
		T.equal(table.concat(active, ","), "MaxScale")
	end)

	test("AC3: hints of the other Place never show; a condition that does not hold shows nothing", function()
		local tutorial = fresh()
		local _, active = core.select("Lobby", tutorial, SIM_ALL, {})
		T.equal(#active, 0)
		_, active = core.select("Simulator", tutorial, all({ "LobbyMove" }), {})
		T.equal(#active, 0)
		_, active = core.select("Arena", tutorial, SIM_ALL, {})
		T.equal(#active, 0)
		local showing = { Controls = "LobbyMove" }
		_, active = core.select("Simulator", tutorial, {}, showing)
		T.equal(#active, 0, "a latched hint of another Place is dropped")
	end)

	test("AC9 6.5 Laden: without a loaded profile nothing shows, never as a new player", function()
		local _, active = core.select("Lobby", nil, all({ "LobbyMove" }), {})
		T.equal(#active, 0)
		_, active = core.select("Simulator", "broken", SIM_ALL, { Controls = "ZoneMove" })
		T.equal(#active, 0)
		T.equal(#core.doneList(nil), 0)
		T.equal(core.markDone(nil, "LobbyMove"), false)
	end)

	test("AC3/AC6: markDone only sets known ids to true, once; nothing sets a hint back", function()
		local tutorial = fresh()
		T.equal(core.markDone(tutorial, "NoSuchHint"), false)
		T.equal(next(tutorial.hints), nil)
		T.equal(core.markDone(tutorial, "MaxScale"), true)
		T.equal(core.markDone(tutorial, "MaxScale"), false, "already done")
		T.equal(tutorial.hints.MaxScale, true)
		-- A broken stored value (not a table) is replaced by a set, never read as "seen".
		local broken = fresh()
		broken.hints = "x"
		T.equal(core.isDone(broken, "ZoneMove"), false)
		T.equal(core.markDone(broken, "ZoneMove"), true)
		T.equal(broken.hints.ZoneMove, true)
	end)

	test("Studio reset clears this module's hints and leaves seenSingleArrow to PortalService", function()
		local tutorial = fresh()
		tutorial.seenSingleArrow = true
		core.markDone(tutorial, "LobbyMove")
		core.markDone(tutorial, "LobbyMultiArrow")
		tutorial.firstMatchHints = true
		T.isTrue(core.reset(tutorial))
		T.equal(next(tutorial.hints), nil)
		T.equal(tutorial.seenMultiArrow, false)
		T.equal(tutorial.firstMatchHints, false)
		T.equal(tutorial.seenSingleArrow, true)
		T.equal(core.reset(nil), false)
	end)

	test("AC6: a client report counts only for a reportable hint that is showing", function()
		T.equal((core.checkReport("UpgradesButton", { "UpgradesButton" })), true)
		local ok, refusal = core.checkReport("UpgradesButton", { "EggStation" })
		T.equal(ok, false)
		T.equal(refusal, "NotActive")
		for _, value in { "ZoneMove", "MaxScale", "", 5, nil, {}, "UpgradesButton,ZoneMove" } do
			ok, refusal = core.checkReport(value, { "ZoneMove", "MaxScale", "UpgradesButton" })
			T.equal(ok, false, `{tostring(value)} refused`)
			T.equal(refusal, "NotReportable")
		end
	end)

	test("AC3: moving ends the controls hint; teleports and respawns do not count", function()
		local walked = core.walk(0, nil, nil, 10, 10)
		T.equal(walked, 0, "the first check only sets the start")
		walked = core.walk(walked, 0, 0, 3, 4)
		T.equal(walked, 5)
		T.equal(core.moved(walked), false)
		walked = core.walk(walked, 0, 0, 0, TutorialConfig.MaxStepPerCheck + 1)
		T.equal(walked, 5, "a jump longer than MaxStepPerCheck is a teleport")
		walked = core.walk(walked, 0, 0, 0 / 0, 0)
		T.equal(walked, 5, "NaN adds nothing")
		walked = core.walk(walked, 0, 0, TutorialConfig.MoveDoneDistance - walked, 0)
		T.equal(walked, TutorialConfig.MoveDoneDistance)
		T.equal(core.moved(walked), true)
	end)

	test("boxDistance: zero inside, distance to the nearest face or edge outside", function()
		T.equal(TutorialCore.boxDistance(0, 0, 0, 4, 4, 4), 0)
		T.equal(TutorialCore.boxDistance(2, 0, 0, 4, 4, 4), 0)
		T.equal(TutorialCore.boxDistance(5, 0, 0, 4, 4, 4), 3)
		T.equal(TutorialCore.boxDistance(5, 6, 0, 4, 4, 4), 5)
		T.equal(TutorialCore.boxDistance(-5, 0, 0, 4, 4, 4), 3)
	end)
end)

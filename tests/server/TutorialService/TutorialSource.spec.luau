--!strict
-- Wiring checks for the Roblox side of the onboarding hints (#42 AC4, AC6, AC7; ADR 0017):
-- only TutorialCore writes the tutorial fields and never sets a hint back outside the Studio
-- reset; the Studio switches are behind the Studio + PlaceId 0 gate; the one client report goes
-- through the guarded Net remote; no store access outside DataService; the HUD is not edited.

local fs = require("@lune/fs")
local T = require("../../TestKit")
local SourceSection = require("../../helpers/SourceSection")

local SERVICE = "src/server/Services/TutorialService"

local function collect(dir: string, out: { [string]: string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			out[path] = fs.readFile(path)
		end
	end
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return T.suite("TutorialService source rules", function(test)
	test("AC4: only TutorialCore writes the tutorial hints and seenMultiArrow", function()
		local files = {}
		collect("src", files)
		for path, text in files do
			local writes = string.find(text, "seenMultiArrow%s*=") ~= nil
				or string.find(text, "%.hints%s*=") ~= nil
				or string.find(text, "%.hints%[[^%]]*%]%s*=") ~= nil
			if path ~= `{SERVICE}/TutorialCore.luau` and path ~= "src/server/Services/DataService/Schema.luau" then
				T.equal(writes, false, `{path} writes a tutorial field`)
			end
		end
	end)

	test("AC3: nothing but the Studio reset sets a hint back to unseen", function()
		local text = fs.readFile(`{SERVICE}/TutorialCore.luau`)
		local reset = SourceSection.between(
			`{SERVICE}/TutorialCore.luau`,
			"local function reset(",
			"local function requiresDone("
		)
		local _, falseWrites = string.gsub(text, "seenMultiArrow = false", "")
		T.equal(falseWrites, 1, "one seenMultiArrow = false")
		T.isTrue(has(reset, "seenMultiArrow = false"), "and it is in reset")
		T.isTrue(has(reset, "tutorial.hints = {}"), "the hints set is emptied only in reset")
		local resetCaller = fs.readFile(`{SERVICE}/init.luau`)
		local _, resets = string.gsub(resetCaller, "core%.reset%(", "")
		T.equal(resets, 1, "one caller")
		T.isTrue(
			has(
				SourceSection.between(
					`{SERVICE}/init.luau`,
					"local function resetFor(",
					"function TutorialService.Start"
				),
				"core.reset("
			)
		)
	end)

	test("Studio switches are bound only behind the Studio + PlaceId 0 gate", function()
		local init = fs.readFile(`{SERVICE}/init.luau`)
		T.isTrue(has(init, "local studioTools = RunService:IsStudio() and game.PlaceId == 0"))
		local _, binds = string.gsub(init, "TutorialSwitches%.bind%(", "")
		T.equal(binds, 1)
		local gate = SourceSection.between(
			`{SERVICE}/init.luau`,
			"if studioTools then\n\t\tTutorialSwitches.bind(",
			"task.spawn("
		)
		T.isTrue(has(gate, "TutorialSwitches.bind("), "bind sits inside the gate")
	end)

	test("AC6: the client report goes only through NetService.handle on the declared remote", function()
		local init = fs.readFile(`{SERVICE}/init.luau`)
		T.isTrue(has(init, 'local REMOTE = "TutorialHintDone"'))
		T.isTrue(has(init, "NetService.handle(REMOTE, onReport)"))
		local onReport =
			SourceSection.between(`{SERVICE}/init.luau`, "local function onReport(", "local function resetFor(")
		T.isTrue(has(onReport, "core.checkReport(id"), "the handler checks the id against the showing hints")
		for path, text in { [`{SERVICE}/init.luau`] = init } do
			for _, needle in { "OnServerEvent", "DataStoreService", "SetAsync", "UpdateAsync" } do
				T.equal(has(text, needle), false, `{path} uses {needle}`)
			end
		end
	end)

	test("the HUD code is not edited: the Upgrades button is found by name", function()
		local hint = fs.readFile("src/places/simulator/client/TutorialController/UpgradesHint.luau")
		T.isTrue(has(hint, 'local HUD_NAME = "SimulatorHud"'))
		T.isTrue(has(hint, 'local BUTTON_NAME = "UpgradesButton"'))
		local hud = fs.readFile("src/places/simulator/client/SimulatorHudController/init.luau")
		T.equal(has(hud, "Tutorial"), false, "the HUD knows nothing of the hints")
	end)
end)

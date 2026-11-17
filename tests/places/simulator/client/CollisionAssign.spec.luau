--!strict
-- Client-side collision group choice (issue #33 AC5, ADR 0003 rev. 2), plus source checks
-- that keep the reviewed design: no CanCollide = false on balls and no remote in the ball code
-- (AC7: the client never sends a size).

local fs = require("@lune/fs")
local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local CollisionAssign = require("../../../../src/places/simulator/client/CollisionController/CollisionAssign")

local SIMULATOR_DIR = "src/places/simulator"

local function collect(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

local function offenders(pattern: string): { string }
	local files = {}
	collect(SIMULATOR_DIR, files)
	local found = {}
	for _, path in files do
		local lineNumber = 0
		for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
			lineNumber += 1
			-- Comments may name what the code does not do.
			local code = string.gsub(line, "%-%-.*$", "")
			if string.find(code, pattern) then
				table.insert(found, `{path}:{lineNumber}`)
			end
		end
	end
	return found
end

return T.suite("Simulator CollisionAssign (ADR 0003 rev. 2 + ADR 0002)", function(test)
	local groups = BallConfig.CollisionGroups

	test("own ball -> OwnBall, every other ball -> Balls", function()
		T.equal(CollisionAssign.groupForBall(42, 42, groups), "OwnBall")
		T.equal(CollisionAssign.groupForBall(7, 42, groups), "Balls")
	end)

	test("a ball without a valid owner is foreign", function()
		T.equal(CollisionAssign.groupForBall(nil, 42, groups), "Balls")
		T.equal(CollisionAssign.groupForBall("42", 42, groups), "Balls")
	end)

	test("own character -> OwnCharacter, every other character -> OtherCharacters", function()
		T.equal(CollisionAssign.groupForCharacter(42, 42, groups), "OwnCharacter")
		T.equal(CollisionAssign.groupForCharacter(7, 42, groups), "OtherCharacters")
		T.equal(CollisionAssign.groupForCharacter(nil, 42, groups), "OtherCharacters")
		T.equal(CollisionAssign.groupForCharacter("42", 42, groups), "OtherCharacters")
	end)

	test("no simulator code sets CanCollide on a part (rejected in review)", function()
		-- The frontier keeps RespectCanCollide (a query option of SafeSpot, #94) out of the match.
		local pattern = "%f[%w]CanCollide%s*="
		T.isTrue(string.find("part.CanCollide = false", pattern) ~= nil, "still finds a part write")
		T.isTrue(string.find("CanCollide=false", pattern) ~= nil, "still finds a bare write")
		T.equal(string.find("params.RespectCanCollide = true", pattern), nil, "ignores the query option")
		local found = offenders(pattern)
		T.equal(#found, 0, table.concat(found, ", "))
	end)

	test("no simulator code fires or handles a remote (the client never sends a size)", function()
		-- The exceptions: the Upgrades window (#36, ADR 0010) sends only an upgrade id through the
		-- declared UpgradeBuy remote, ZoneRequests (#39, ADR 0014) only a zone number through
		-- ZoneUnlock and ZoneTeleport, and the onboarding hints (#42, ADR 0017) only the hint id
		-- "UpgradesButton" on TutorialHintDone. Never a size, level, price or position.
		local upgradesPanel = `{SIMULATOR_DIR}/client/SimulatorHudController/UpgradesPanel.luau`
		local zoneRequests = `{SIMULATOR_DIR}/client/ZoneController/ZoneRequests.luau`
		local tutorial = `{SIMULATOR_DIR}/client/TutorialController/init.luau`
		local function allowed(place: string): boolean
			for _, path in { upgradesPanel, zoneRequests, tutorial } do
				if string.sub(place, 1, #path + 1) == `{path}:` then
					return true
				end
			end
			return false
		end
		for _, pattern in { "FireServer", "OnServerEvent", "InvokeServer", "OnServerInvoke", "RemoteEvent" } do
			local found = {}
			for _, place in offenders(pattern) do
				if not allowed(place) then
					table.insert(found, place)
				end
			end
			T.equal(#found, 0, `{pattern}: {table.concat(found, ", ")}`)
		end
		local requests = fs.readFile(zoneRequests)
		local _, zoneFires = string.gsub(requests, "FireServer%(", "")
		T.equal(zoneFires, 2, "ZoneRequests fires two remote calls")
		local _, zoneOnly = string.gsub(requests, "remote:FireServer%(zone%)", "")
		T.equal(zoneOnly, 2, "both send only the zone")
		local panel = fs.readFile(upgradesPanel)
		local _, fires = string.gsub(panel, "FireServer%(", "")
		T.equal(fires, 1, "the Upgrades window fires one remote call")
		T.isTrue(string.find(panel, "remote:FireServer(id)", 1, true) ~= nil, "and sends only the id")
		T.isTrue(string.find(panel, 'local REMOTE = "UpgradeBuy"', 1, true) ~= nil, "on UpgradeBuy")
		local hints = fs.readFile(tutorial)
		local _, hintFires = string.gsub(hints, "FireServer%(", "")
		T.equal(hintFires, 1, "the onboarding hints fire one remote call")
		T.isTrue(string.find(hints, 'remote:FireServer("UpgradesButton")', 1, true) ~= nil, "with only the hint id")
		T.isTrue(string.find(hints, 'Net.waitForRemote("TutorialHintDone")', 1, true) ~= nil, "on TutorialHintDone")
	end)
end)

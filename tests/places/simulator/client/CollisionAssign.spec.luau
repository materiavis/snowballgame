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

return T.suite("Simulator CollisionAssign (ADR 0003 rev. 2)", function(test)
	local groups = BallConfig.CollisionGroups

	test("own ball -> OwnBall, every other ball -> Balls", function()
		T.equal(CollisionAssign.groupForBall(42, 42, groups), "OwnBall")
		T.equal(CollisionAssign.groupForBall(7, 42, groups), "Balls")
	end)

	test("a ball without a valid owner is foreign", function()
		T.equal(CollisionAssign.groupForBall(nil, 42, groups), "Balls")
		T.equal(CollisionAssign.groupForBall("42", 42, groups), "Balls")
	end)

	test("no simulator code sets CanCollide on a part (rejected in review)", function()
		local found = offenders("CanCollide%s*=")
		T.equal(#found, 0, table.concat(found, ", "))
	end)

	test("no simulator code fires or handles a remote (the client never sends a size)", function()
		for _, pattern in { "FireServer", "OnServerEvent", "InvokeServer", "OnServerInvoke", "RemoteEvent" } do
			local found = offenders(pattern)
			T.equal(#found, 0, `{pattern}: {table.concat(found, ", ")}`)
		end
	end)
end)

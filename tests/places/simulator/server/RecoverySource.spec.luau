--!strict
-- Source checks for the recovery (issue #94, ADR 0002 "Recovery"): the Studio log names reason,
-- ball, character and put-back position; the fall check waits for the grace time; the old
-- placement in front is only the last fallback; the test geometry is only bound behind the
-- Studio gate. Runtime behaviour is for the playtest.

local fs = require("@lune/fs")
local T = require("../../../TestKit")

local DIR = "src/places/simulator/server/BallService"

local function read(name: string): string
	return fs.readFile(`{DIR}/{name}`)
end

return T.suite("Simulator recovery source (#94)", function(test)
	test("every recovery logs reason, ball, character and put-back position in Studio", function()
		local source = read("Recovery.luau")
		local start = string.find(source, "if deps.verbose then%s+print%(%s+`%[BallService%] {name} recovery")
		T.isTrue(start ~= nil, "a verbose-gated recovery print")
		local line = string.sub(source, start :: number, (start :: number) + 400)
		for _, field in { "reason={why}", "ball={show(ballBefore)}", "character={show(root.Position)}", "putBack=" } do
			T.isTrue(string.find(line, field, 1, true) ~= nil, field)
		end
		T.isTrue(string.find(read("init.luau"), "verbose = studioTools", 1, true) ~= nil, "gated by studioTools")
	end)

	test("the fall check skips the grace time after a placement", function()
		local source = read("BallStep.luau")
		local grace = string.find(source, "recoveryRules.inGrace", 1, true)
		local fell = string.find(source, '"fell"', 1, true)
		T.isTrue(grace ~= nil and fell ~= nil and (grace :: number) < (fell :: number))
	end)

	test("the old placement in front is only SafeSpot's last fallback", function()
		local init = read("init.luau")
		T.isTrue(string.find(init, "fallback = ballPart.spawnPosition", 1, true) ~= nil)
		local _, uses = string.gsub(init, "spawnPosition", "")
		T.equal(uses, 1, "init uses spawnPosition only as the fallback")
	end)

	test("the test geometry is reachable only from the Studio switches", function()
		local init = read("init.luau")
		local setUp = string.find(init, "local function setUpStudio", 1, true)
		local create = string.find(init, "TestGeometry.create", 1, true)
		T.isTrue(setUp ~= nil and create ~= nil and (create :: number) > (setUp :: number), "inside setUpStudio")
		T.isTrue(string.find(init, "if studioTools then%s+setUpStudio%(%)") ~= nil, "setUpStudio is gated")
	end)
end)

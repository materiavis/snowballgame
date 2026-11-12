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
		local fields =
			{ "reason={why}", "ball={show(ballBefore)}", "character={show(root.Position)}", "putBack=", "loop=" }
		for _, field in fields do
			T.isTrue(string.find(line, field, 1, true) ~= nil, field)
		end
		T.isTrue(string.find(read("init.luau"), "verbose = studioTools", 1, true) ~= nil, "gated by studioTools")
	end)

	test("both bounds park the ball, and the Recoveries count is written on every recovery", function()
		local source = read("Recovery.luau")
		T.isTrue(string.find(source, "if bounded then%s+park%(state, now%)") ~= nil, "burst bound parks")
		T.isTrue(string.find(source, "elseif looped then%s+park%(state, now%)") ~= nil, "loop bound parks")
		local written = string.find(source, "state.part:SetAttribute(config.RecoveriesAttribute", 1, true)
		T.isTrue(written ~= nil, "Recoveries written in recover, outside the Studio gate")
	end)

	test("the client hold follows the server's Recoveries attribute", function()
		local source = fs.readFile("src/places/simulator/client/BallController/init.luau")
		T.isTrue(
			string.find(source, "GetAttributeChangedSignal(BallConfig.RecoveriesAttribute)", 1, true) ~= nil,
			"listens to the replicated count"
		)
		T.isTrue(
			string.find(source, "GetAttributeChangedSignal(BallConfig.PlacementsAttribute)", 1, true) ~= nil,
			"and to placements that are not recoveries"
		)
		T.isTrue(string.find(source, "hold.followsBall(", 1, true) ~= nil, "uses the reset window")
		T.isTrue(string.find(source, "PlaceId", 1, true) == nil, "not limited to Studio")
	end)

	test("the stuck rule uses the slope reach, the growth rule stays as it is", function()
		local source = read("BallStep.luau")
		T.isTrue(string.find(source, "inRange = heldForStuck(", 1, true) ~= nil, "stuck uses heldForStuck")
		T.isTrue(string.find(source, "recoveryRules.heldOnSlope(", 1, true) ~= nil)
		T.isTrue(string.find(source, "inRange = rules.inGrowthRange(", 1, true) ~= nil, "growth unchanged")
		T.isTrue(string.find(read("SafeSpot.luau"), "recoveryRules.restingHeight(", 1, true) ~= nil)
	end)

	test("BallPlaceBehindObstacle is Studio-only and no recovery", function()
		local init = read("init.luau")
		local setUp = string.find(init, "local function setUpStudio", 1, true)
		local new = string.find(init, "PlaceBehind.new(", 1, true)
		T.isTrue(setUp ~= nil and new ~= nil and (new :: number) > (setUp :: number), "built inside setUpStudio")
		local source = read("PlaceBehind.luau")
		for _, forbidden in { "recover(", "SetAttribute", "recentRecoveries", "recentPutBacks" } do
			T.isTrue(string.find(source, forbidden, 1, true) == nil, `no {forbidden}`)
		end
		T.isTrue(string.find(source, "BallPlaceBehindObstacle", 1, true) ~= nil, "own log line")
		local recovery = read("Recovery.luau")
		local moveTo = string.find(recovery, "local function moveTo", 1, true) :: number
		local body = string.sub(recovery, moveTo, moveTo + 200)
		T.isTrue(string.find(body, "countPlacement(state)", 1, true) ~= nil, "counts a placement")
		T.isTrue(string.find(body, "RecoveriesAttribute", 1, true) == nil, "not a recovery")
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

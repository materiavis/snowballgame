--!strict
-- Source checks for issue #97 (ADR 0002 "After a hit"): the server sample passes the same-hit
-- memory to ObstacleRules and steps the rebound watch; the log and trace are Studio-only; the
-- switch BallRunAtObstacle is Studio-only and no recovery; the client uses the rebound brake
-- and still sends nothing. Runtime behaviour is for the playtest.

local fs = require("@lune/fs")
local T = require("../../../TestKit")

local DIR = "src/places/simulator/server/BallService"

local function read(name: string): string
	return fs.readFile(`{DIR}/{name}`)
end

local function has(source: string, text: string): boolean
	return string.find(source, text, 1, true) ~= nil
end

return T.suite("Simulator after-hit source (#97)", function(test)
	test("the server sample uses the same-hit memory and the rebound watch", function()
		local step = read("BallStep.luau")
		T.isTrue(has(step, "deps.afterHit.sameHitCheck(state, position, radius)"), "same-hit check to evaluate")
		T.isTrue(has(step, "deps.afterHit.noteOutcome(state, outcome, counted"), "outcome noted")
		T.isTrue(has(step, "deps.afterHit.step(state, position, livingRoot(state), now, elapsed)"), "watch stepped")
		local handle = string.find(step, "handleObstacles(state, position", 1, true) :: number
		local watch = string.find(step, "deps.afterHit.step(", 1, true) :: number
		local last = string.find(step, "state.lastPosition = position", 1, true) :: number
		T.isTrue(handle < watch and watch < last, "watch after the obstacles, before lastPosition moves")
	end)

	test("log lines and the trace are written only in Studio at PlaceId 0", function()
		local source = read("AfterHit.luau")
		local _, prints = string.gsub(source, "print%(", "")
		local _, gated = string.gsub(source, "if deps%.verbose", "")
		T.equal(prints, 3, "touch, rebound and trace lines")
		T.equal(gated, 3, "each behind deps.verbose")
		T.isTrue(has(source, "deps.verbose and deps.isTracing()"), "trace needs the switch too")
		local init = read("init.luau")
		T.isTrue(has(init, "verbose = studioTools,"), "verbose is the Studio gate")
		for _, field in { "ball={show(", "character={show(", "beyondHold=", "result={result}" } do
			T.isTrue(has(source, field), field)
		end
	end)

	test("BallRunAtObstacle is Studio-only and no recovery", function()
		local init = read("init.luau")
		local setUp = string.find(init, "local function setUpStudio", 1, true)
		local new = string.find(init, "RunAtObstacle.new(", 1, true)
		T.isTrue(setUp ~= nil and new ~= nil and (new :: number) > (setUp :: number), "built inside setUpStudio")
		local source = read("RunAtObstacle.luau")
		for _, forbidden in { "recover(", "SetAttribute", "recentRecoveries", "recentPutBacks" } do
			T.isTrue(not has(source, forbidden), `no {forbidden}`)
		end
		T.isTrue(has(source, "deps.moveTo(state, ball)"), "moves the ball like BallPlaceBehindObstacle")
		local switches = read("StudioSwitches.luau")
		T.isTrue(has(switches, '"BallRunAtObstacle"') and has(switches, '"BallHitTrace"'))
	end)

	test("the client holds with the rebound brake and sends nothing", function()
		local source = fs.readFile("src/places/simulator/client/BallController/init.luau")
		T.isTrue(has(source, "hold.holdAcceleration("), "rebound brake in the hold")
		for _, forbidden in { "FireServer", "InvokeServer", "RemoteEvent", "PlaceId" } do
			T.isTrue(not has(source, forbidden), `no {forbidden}`)
		end
	end)
end)

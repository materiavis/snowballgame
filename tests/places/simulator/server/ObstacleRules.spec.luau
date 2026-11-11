--!strict
-- ObstacleRules (issue #34, concept 7.4, ADR 0002): contact distance and what a set of touches
-- costs, on the real Config.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local ObstacleRules = require("../../../../src/places/simulator/server/BallService/ObstacleRules")

local rules = ObstacleRules.new(BallConfig :: any)

local function never(_size: any): boolean
	return false
end

local function always(_size: any): boolean
	return true
end

return T.suite("Simulator ObstacleRules (7.4)", function(test)
	test("distance to a box: inside, along a face, past a corner", function()
		T.equal(rules.boxDistance(0, 0, 0, 2, 2, 2), 0, "inside")
		T.near(rules.boxDistance(5, 0, 0, 2, 2, 2), 3, 1e-9, "face")
		T.near(rules.boxDistance(5, 6, 0, 2, 2, 2), 5, 1e-9, "edge (3-4-5)")
	end)

	test("touching includes the configured margin", function()
		local margin = BallConfig.CollisionContactMargin
		T.equal(rules.isTouching(2 + margin - 0.01, 2), true)
		T.equal(rules.isTouching(2 + margin + 0.01, 2), false)
	end)

	test("AC3: a new touch is a collision, a touch inside the protection time is not", function()
		local hit = rules.evaluate({}, { { obstacle = "tree" } }, false, never)
		T.equal(hit.hit, true, "first collision")
		local protected = rules.evaluate({}, { { obstacle = "rock" } }, true, never)
		T.equal(protected.hit, false, "protected")
	end)

	test("pressing against the same obstacle is one collision", function()
		local first = rules.evaluate({}, { { obstacle = "tree" } }, false, never)
		local second = rules.evaluate(first.contacts, { { obstacle = "tree" } }, false, never)
		T.equal(first.hit, true)
		T.equal(second.hit, false, "still touching: no new collision")
		local away = rules.evaluate(second.contacts, {}, false, never)
		local again = rules.evaluate(away.contacts, { { obstacle = "tree" } }, false, never)
		T.equal(again.hit, true, "rolled away and back in")
	end)

	test("the first sample after placing the ball has no effect", function()
		local placed = rules.evaluate(nil, { { obstacle = "tree" } }, false, never)
		T.equal(placed.hit, false)
		T.equal(#placed.knockOvers, 0)
		T.equal(placed.contacts["tree"], true, "remembered")
	end)

	test("a contact first seen during the protection after placing never costs size", function()
		local placed = rules.evaluate(nil, {}, true, never)
		T.equal(placed.hit, false, "first sample: no contact yet")
		local seen = rules.evaluate(placed.contacts, { { obstacle = "tree" } }, true, never)
		T.equal(seen.hit, false, "second sample: contact while protected")
		local after = rules.evaluate(seen.contacts, { { obstacle = "tree" } }, false, never)
		T.equal(after.hit, false, "third sample: same contact, protection over")
	end)

	test("7.4 knock-over: no size loss, even while protected", function()
		local outcome = rules.evaluate({}, { { obstacle = "fence", knockOverSize = 1 } }, false, always)
		T.equal(outcome.hit, false, "no loss")
		T.equal(outcome.knockOvers[1], "fence")
		local protected = rules.evaluate({}, { { obstacle = "fence", knockOverSize = 1 } }, true, always)
		T.equal(protected.knockOvers[1], "fence", "protection does not matter")
	end)

	test("an obstacle the ball is too small for costs size", function()
		local outcome = rules.evaluate({}, { { obstacle = "fence", knockOverSize = 1 } }, false, never)
		T.equal(outcome.hit, true)
		T.equal(#outcome.knockOvers, 0)
	end)
end)

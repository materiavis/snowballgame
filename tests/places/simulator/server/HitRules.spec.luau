--!strict
-- HitRules (issue #97, ADR 0002 "After a hit"): the same-hit memory (D2) and the rebound watch
-- (D1 limit), on the real Config. Together with ObstacleRules: one hit with the character
-- pushing on costs at most one collision, replayed on the run A pattern of #34.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local HitRules = require("../../../../src/places/simulator/server/BallService/HitRules")
local ObstacleRules = require("../../../../src/places/simulator/server/BallService/ObstacleRules")

local hits = HitRules.new(BallConfig :: any)
local obstacleRules = ObstacleRules.new(BallConfig :: any)
local SEPARATION = BallConfig.CollisionSeparationStuds

local function never(_size: any): boolean
	return false
end

-- Runs samples of { gap = studs from the ball's surface to "tree" } through the same order as
-- BallStep: forget, evaluate, remember; protection as in BallStep.applyCollision. Returns the
-- number of counted collisions and of same-hit repeats.
local function replay(gaps: { number }, interval: number): (number, number)
	local memory: HitRules.Memory = {}
	local contacts: { [any]: boolean }? = {}
	local protectedUntil = 0
	local collisions, repeats = 0, 0
	for index, gap in gaps do
		local now = index * interval
		hits.forget(memory, function(_obstacle: any): number?
			return gap
		end)
		local current = {}
		if gap <= BallConfig.CollisionContactMargin then
			table.insert(current, { obstacle = "tree" })
		end
		local outcome = obstacleRules.evaluate(contacts, current, now < protectedUntil, never, function(o: any): boolean
			return memory[o] == true
		end)
		hits.remember(memory, outcome.contacts)
		contacts = outcome.contacts
		repeats += #outcome.repeats
		if outcome.hit then
			collisions += 1
			protectedUntil = now + BallConfig.CollisionProtection
		end
	end
	return collisions, repeats
end

return T.suite("Simulator HitRules (#97)", function(test)
	test("the memory keeps an obstacle until the ball is CollisionSeparationStuds clear of it", function()
		local memory: HitRules.Memory = {}
		hits.remember(memory, { tree = true })
		hits.forget(memory, function(): number?
			return SEPARATION - 0.01
		end)
		T.equal(memory["tree"], true, "just inside the separation")
		hits.forget(memory, function(): number?
			return SEPARATION
		end)
		T.equal(memory["tree"], nil, "clearly away")
		hits.remember(memory, { rock = true })
		hits.forget(memory, function(): number?
			return nil
		end)
		T.equal(memory["rock"], nil, "knocked over or gone")
	end)

	test("D2: the run A pattern (pressing, rebounds into the same obstacle) costs one collision", function()
		-- Point 11 of run A at 108db61: 4 collisions within about 12 s on SmallObstacle, the ball
		-- bouncing off and back. Here: contact, 2 s away up to 3 studs, back, five times.
		local gaps = {}
		for _ = 1, 5 do
			for _ = 1, 10 do
				table.insert(gaps, 0)
			end
			for step = 1, 20 do
				table.insert(gaps, 3 * math.sin(step / 20 * math.pi))
			end
		end
		local collisions, repeats = replay(gaps, BallConfig.SampleInterval)
		T.equal(collisions, 1, "one hit")
		T.equal(repeats, 5, "every rebound back into it recognised as the same hit")
	end)

	test("D2: a rebound right up to the separation still counts once; even 10 s away does not matter", function()
		local gaps = { 0, 0 }
		for _ = 1, 100 do
			table.insert(gaps, SEPARATION - 0.5)
		end
		table.insert(gaps, 0)
		local collisions, repeats = replay(gaps, BallConfig.SampleInterval)
		T.equal(collisions, 1)
		T.equal(repeats, 1)
	end)

	test("D2: backing off clearly and rolling in again is a new collision", function()
		local collisions, repeats = replay({ 0, 0, 2, 4, SEPARATION, SEPARATION + 2, 4, 2, 0 }, 0.5)
		T.equal(collisions, 2)
		T.equal(repeats, 0)
	end)

	test("D1 watch: most studs beyond the hold distance and the time until it settled", function()
		local watch = hits.startWatch(10, "tree", "hit")
		hits.stepWatch(watch, 10, -0.5, "pressed")
		hits.stepWatch(watch, 10.1, 2.4, "max")
		hits.stepWatch(watch, 10.2, 1.5, "coming back")
		hits.stepWatch(watch, 10.3, 0.4, "back")
		T.equal(hits.isWatchOver(watch, 10 + BallConfig.ReboundWatchTime - 0.01), false)
		T.equal(hits.isWatchOver(watch, 10 + BallConfig.ReboundWatchTime), true)
		local summary = hits.summarize(watch)
		T.near(summary.studs, 2.4, 1e-9)
		T.near(summary.seconds, 0.2, 1e-9)
		T.equal(summary.within, true)
		T.equal(watch.atMax, "max", "positions of the farthest sample for the log")
	end)

	test("D1 watch: a ball that goes too far or stays out too long is outside the limit", function()
		local far = hits.startWatch(0, "tree", "hit")
		hits.stepWatch(far, 0.1, BallConfig.ReboundMaxStuds + 0.1, nil)
		T.equal(hits.summarize(far).within, false, "too far")
		local long = hits.startWatch(0, "tree", "hit")
		hits.stepWatch(long, BallConfig.ReboundMaxSeconds + 0.1, BallConfig.ReboundSettleStuds + 0.1, nil)
		T.equal(hits.summarize(long).within, false, "too long")
		local pressed = hits.startWatch(0, "tree", "hit")
		hits.stepWatch(pressed, 0.1, -1, nil)
		local summary = hits.summarize(pressed)
		T.equal(summary.studs, 0, "never beyond the hold distance")
		T.equal(summary.within, true)
	end)

	test("the proposed values fit together", function()
		T.isTrue(SEPARATION >= 2 * BallConfig.ReboundMaxStuds, "a rebound inside the limit never separates")
		T.isTrue(BallConfig.ReboundMaxSeconds <= BallConfig.ReboundWatchTime)
		T.isTrue(BallConfig.ReboundSettleStuds < BallConfig.ReboundMaxStuds)
		T.isTrue(
			BallConfig.HoldGap + BallConfig.ReboundMaxStuds < BallConfig.GrowthRange,
			"a ball at the limit is still in growth range"
		)
		T.isTrue(BallConfig.HoldReboundMaxAcceleration > BallConfig.HoldMaxAcceleration)
	end)
end)

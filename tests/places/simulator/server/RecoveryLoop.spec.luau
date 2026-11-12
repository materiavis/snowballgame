--!strict
-- Same-place loop bound (issue #94 correction round 1, ADR 0002 "Recovery"): the playtest at
-- f95545a saw `fell` recoveries about 5 s apart at the map edge, which the burst rule (3 in
-- 5 s) never reaches. These checks run the rule on the real Config, in the same order as
-- Recovery.recover: drop old put-backs, count the near ones, then add the new one.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local RecoveryRules = require("../../../../src/places/simulator/server/BallService/RecoveryRules")

local rules = RecoveryRules.new(BallConfig :: any)

-- Recoveries at the given times and put-back positions; returns the index of the first one
-- past the loop bound and of the first one past the burst bound (nil = none).
local function run(times: { number }, place: (index: number) -> (number, number), diameter: number): (number?, number?)
	local putBacks: { any } = {}
	local burst: { number } = {}
	local loopAt, burstAt = nil, nil
	for index, now in times do
		local x, z = place(index)
		putBacks = rules.recentPutBacks(putBacks, now)
		if rules.atLoopBound(rules.nearPutBacks(putBacks, x, z, diameter)) and loopAt == nil then
			loopAt = index
		end
		table.insert(putBacks, { time = now, x = x, z = z })
		burst = rules.recentRecoveries(burst, now)
		if rules.atBound(#burst) and burstAt == nil then
			burstAt = index
		end
		table.insert(burst, now)
	end
	return loopAt, burstAt
end

local function every(seconds: number, count: number): { number }
	local times: { number } = {}
	for index = 0, count - 1 do
		table.insert(times, index * seconds)
	end
	return times
end

-- The put-back of the playtest: spot Around at (219, -999), the character standing still.
local function samePlace(_index: number): (number, number)
	return 219, -999
end

return T.suite("Simulator recovery loop bound (7.3, #94)", function(test)
	test("the playtest loop (fell about 5 s apart, same spot) is parked at its 4th recovery", function()
		local loopAt, burstAt = run(every(5, 12), samePlace, 50)
		T.equal(burstAt, nil, "the burst rule alone never parks it (the f95545a finding)")
		T.equal(loopAt, BallConfig.RecoveryLoopLimit + 1, "parked at the first recovery past the loop limit")
	end)

	test("slower loops up to about 13 s per round are caught too", function()
		local slowest = BallConfig.RecoveryLoopWindow / BallConfig.RecoveryLoopLimit
		for _, seconds in { 2, 5, 8, 10, slowest - 0.1 } do
			local loopAt = run(every(seconds, 12), samePlace, 50)
			T.equal(loopAt, BallConfig.RecoveryLoopLimit + 1, `{seconds} s per round`)
		end
	end)

	test("losing the ball now and then at the same place stays below the bound", function()
		local slowest = BallConfig.RecoveryLoopWindow / BallConfig.RecoveryLoopLimit
		local loopAt = run(every(slowest + 0.5, 20), samePlace, 50)
		T.equal(loopAt, nil, `one recovery every {slowest + 0.5} s`)
	end)

	test("recoveries at different places stay below the bound, even 5 s apart", function()
		-- Walking along the edge: each put-back one ball diameter and a bit further on.
		local diameter = 50
		local loopAt = run(every(5, 20), function(index: number): (number, number)
			return index * (rules.loopRadius(diameter) + 1), -999
		end, diameter)
		T.equal(loopAt, nil)
	end)

	test("the Studio checks of AC2, AC9 and AC8 (three switch recoveries in place) stay below it", function()
		local loopAt = run({ 0, 6, 12 }, samePlace, 38)
		T.equal(loopAt, nil)
	end)

	test("a ball pushed off the same edge on purpose every 4 s is parked too (by design)", function()
		-- Not distinguishable from the loop on the server; parking only holds it RecoveryParkTime.
		local loopAt, burstAt = run(every(4, 12), samePlace, 50)
		T.equal(burstAt, nil)
		T.equal(loopAt, BallConfig.RecoveryLoopLimit + 1)
	end)

	test("the same-place radius grows with the ball and has a floor", function()
		T.equal(rules.loopRadius(1.6), BallConfig.RecoveryLoopRadiusMin)
		T.equal(rules.loopRadius(50), 50 * BallConfig.RecoveryLoopRadiusPerDiameter)
		T.equal(rules.nearPutBacks({ { time = 0, x = 0, z = 0 } }, 50, 0, 50), 1, "at the radius")
		T.equal(rules.nearPutBacks({ { time = 0, x = 0, z = 0 } }, 50.1, 0, 50), 0, "beyond it")
	end)

	test("old put-backs leave the window", function()
		local window = BallConfig.RecoveryLoopWindow
		local kept = rules.recentPutBacks({ { time = 0, x = 0, z = 0 }, { time = 1, x = 0, z = 0 } }, window + 0.5)
		T.equal(#kept, 1)
		T.equal(kept[1].time, 1)
	end)

	test("the loop window is never shorter than the burst window", function()
		T.isTrue(BallConfig.RecoveryLoopWindow >= BallConfig.RecoveryBurstWindow)
		T.throws(function()
			local config = table.clone(BallConfig) :: any
			config.RecoveryLoopWindow = BallConfig.RecoveryBurstWindow - 1
			RecoveryRules.new(config)
		end, "RecoveryLoopWindow")
	end)
end)

--!strict
-- #39 AC5: the ball keeps its size when it enters the next zone (concept 7.6, decision
-- 2026-10-08). GrowthRules.carryFraction is what BallService.EnterZone applies; ZoneService calls
-- EnterZone on every zone change (checked in ZoneSource.spec).

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local BallConfig = require("../../../../src/shared/Config/Ball")
local GrowthRules = require("../../../../src/places/simulator/server/BallService/GrowthRules")

local rules = GrowthRules.new(BallConfig :: any, E.Zones.maxSize)

return T.suite("Ball keeps its size between zones (#39 AC5)", function(test)
	test("a full zone 1 ball (2 m) is still 2 m in zone 2 and can grow on", function()
		local fraction = rules.carryFraction(1, 1, 2)
		T.near(rules.sizeMetres(2, fraction), 2, 1e-9)
		T.isTrue(fraction < 1, "below the zone 2 maximum of 2.5 m, so it grows on")
		T.near(E.Zones.maxSize(2), 2.5, 1e-9)
	end)

	test("every size of zones 1-4 keeps its metres in the next zone", function()
		for zone = 1, 4 do
			for step = 0, 10 do
				local before = rules.sizeMetres(zone, step / 10)
				local after = rules.sizeMetres(zone + 1, rules.carryFraction(zone, step / 10, zone + 1))
				if before >= rules.startSize(zone + 1) then
					T.near(after, before, 1e-9, `zone {zone} fraction {step / 10}`)
				else
					-- Below the next zone's start size: starts at that start size (a few cm).
					T.near(after, rules.startSize(zone + 1), 1e-9)
				end
			end
		end
	end)

	test("into a lower zone (teleport, walking back) a larger ball is capped at its maximum", function()
		local fraction = rules.carryFraction(5, 1, 1)
		T.equal(fraction, 1)
		T.near(rules.sizeMetres(1, fraction), 2, 1e-9)
		local small = rules.carryFraction(5, 0, 1) -- 0.49 m fits zone 1
		T.near(rules.sizeMetres(1, small), rules.sizeMetres(5, 0), 1e-9)
	end)
end)

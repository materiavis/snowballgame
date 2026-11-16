--!strict
-- #39 AC6 (estimate only): "Ein neuer Spieler erreicht Zone 2 etwa 4 Minuten nach der Ankunft in
-- Zone 1 (Testmessung)". The real measurement needs selling (#38) and the real zone 1 map (#29)
-- and stays pending. This spec checks that the formulas and Config make about 4 minutes
-- plausible, under the assumptions below. The assumptions are test values, not design values.

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")

-- Assumptions of the estimate (not in Config, not game values):
local SELL_SECONDS = 5 -- pushing the full ball onto the scale and starting again (#38)
local COLLISION_SLOWDOWN = 1.3 -- obstacle hits (15-25 per zone, 6.2) cost growth time
local MINUTES_LOW, MINUTES_HIGH = 3, 5 -- "etwa 4 Minuten"

return T.suite("Zone pacing estimate (#39 AC6, pending real measurement)", function(test)
	test("zone 1 to zone 2 takes about 4 minutes of full balls", function()
		local price = E.Zones.barrierPrice(1)
		local ballValue = E.Zones.fullBallValue(1)
		local balls = math.ceil(price / ballValue)
		T.equal(price, 320)
		T.equal(ballValue, 80)
		T.equal(balls, 4, "B(1) = 2 + 2n = 4 balls, M(1) = 1")
		-- Seconds from start size to MAX at upgrade level 0 (Config.Upgrades growth Start).
		local growSeconds = E.Upgrades.effect("growth", 0)
		T.equal(growSeconds, 40)
		local seconds = balls * (growSeconds * COLLISION_SLOWDOWN + SELL_SECONDS)
		local minutes = seconds / 60
		print(string.format("[ZonePacing] estimate zone 1 -> 2: %d balls, %.0f s = %.1f min", balls, seconds, minutes))
		T.isTrue(minutes >= MINUTES_LOW and minutes <= MINUTES_HIGH, `estimate {minutes} min`)
	end)
end)

--!strict
-- Concept 7.6 and 8.4 tables reproduced from the real Config (issue #27 AC1).
-- Exact rows are exact. "ca." rows are within CONCEPT_ROUNDING: the concept rounds them to one
-- or two significant figures, the widest gap is zone 5 (barrier 28,968 shown as "ca. 30K").

local T = require("../../TestKit")
local E = require("../../helpers/Economy")

local Zones = E.Zones
local CONCEPT_ROUNDING = 0.05 -- relative

local function about(actual: number, expected: number, label: string)
	T.near(actual, expected, expected * CONCEPT_ROUNDING, label)
end

return T.suite("Formulas.Zones (7.6, 8.4)", function(test)
	test("7.6 zone 1: 2 m, full ball 80, barrier 320 (exact)", function()
		T.equal(Zones.maxSize(1), 2)
		T.equal(Zones.fullBallValue(1), 80)
		T.equal(Zones.barrierPrice(1), 320)
	end)

	test("7.6 zone 5: 4.9 m, full ball 1.2K, barrier ca. 30K", function()
		T.near(Zones.maxSize(5), 4.9, 0.05, "max size")
		about(Zones.fullBallValue(5), 1.2e3, "full ball")
		about(Zones.barrierPrice(5), 30e3, "barrier")
	end)

	test("7.6 zone 10: 15 m, full ball 33K, barrier ca. 3.8M", function()
		T.near(Zones.maxSize(10), 15, 0.1, "max size")
		about(Zones.fullBallValue(10), 33e3, "full ball")
		about(Zones.barrierPrice(10), 3.8e6, "barrier")
		T.equal(Zones.barrierPrice(10), 3755901, "barrier in whole coins")
	end)

	test("7.6 zone 25: 425 m, full ball 770M, barrier ca. 3.2T", function()
		about(Zones.maxSize(25), 425, "max size")
		about(Zones.fullBallValue(25), 770e6, "full ball")
		about(Zones.barrierPrice(25), 3.2e12, "barrier")
	end)

	test("7.6 zone 49: 90 km, full ball 7 Qa, barrier ca. 4.6 Sx", function()
		about(Zones.maxSize(49), 90e3, "max size")
		about(Zones.fullBallValue(49), 7e15, "full ball")
		about(Zones.barrierPrice(49), 4.6e21, "barrier")
	end)

	test("7.6 full ball = 80 * 1.953^(n - 1) for every zone", function()
		for zone = 1, Zones.zoneCount do
			local expected = 80 * 1.953 ^ (zone - 1)
			T.near(Zones.fullBallValue(zone), expected, expected * 0.005, `zone {zone}`)
		end
	end)

	test("7.6 barrier = full ball * B(n) * M(n) with B(n) = 2 + 2n and M(n) = 1.2^(n - 1)", function()
		for zone = 1, Zones.zoneCount do
			T.equal(Zones.ballsPerBarrier(zone), 2 + 2 * zone, `B({zone})`)
			T.near(Zones.expectedStrength(zone), 1.2 ^ (zone - 1), 1e-9 * 1.2 ^ (zone - 1), `M({zone})`)
			local exact = Zones.fullBallValue(zone) * (2 + 2 * zone) * 1.2 ^ (zone - 1)
			T.isTrue(Zones.barrierPrice(zone) <= exact + 1e-6 * exact, `zone {zone} rounded down`)
			T.isTrue(Zones.barrierPrice(zone) > exact - 1 - 1e-12 * exact, `zone {zone} within a coin`)
		end
	end)

	test("8.4 progression: zone 2 ca. 320, zone 5 ca. 10K, zone 6 ca. 30K, zone 10 ca. 1.5M", function()
		-- The cost to reach zone n is the barrier at the end of zone n - 1.
		T.equal(Zones.barrierPrice(1), 320, "zone 2")
		T.near(Zones.maxSize(2), 2.5, 1e-9, "zone 2 ball up to 2.5 m")
		about(Zones.barrierPrice(4), 10e3, "zone 5")
		about(Zones.barrierPrice(5), 30e3, "zone 6")
		about(Zones.barrierPrice(9), 1.5e6, "zone 10")
	end)

	test("8.4 world 2: the world gate at the end of zone 10 costs ca. 3.8M", function()
		T.isTrue(Zones.isWorldGate(10), "zone 10 ends in a gate")
		about(Zones.barrierPrice(10), 3.8e6, "gate price")
	end)

	test("worlds: 10 zones each, gates after zones 10, 20, 30 and 40 only", function()
		T.equal(Zones.worldOf(1), 1)
		T.equal(Zones.worldOf(10), 1)
		T.equal(Zones.worldOf(11), 2)
		T.equal(Zones.worldOf(50), 5)
		T.equal(Zones.zoneInWorld(16), 6)
		local gates = {}
		for zone = 1, Zones.zoneCount do
			if Zones.isWorldGate(zone) then
				table.insert(gates, zone)
			end
		end
		T.equal(table.concat(gates, ","), "10,20,30,40")
	end)

	test("7.3 zone optics: 4 studs in zone 1 to 50 studs in zone 50, capped", function()
		T.equal(Zones.zoneOptics(1), 4)
		T.near(Zones.zoneOptics(50), 50, 1e-9, "zone 50")
		local capped = E.Modules.Zones.new(table.clone(E.Config.Zones) :: any)
		T.isTrue(capped.zoneOptics(50) <= E.Config.Zones.VisualCap)
		local lowCap = table.clone(E.Config.Zones) :: any
		lowCap.VisualCap = 30
		T.equal(E.Modules.Zones.new(lowCap).zoneOptics(50), 30, "a lowered cap holds")
	end)

	test("invalid zones and sizes are errors, not silent values", function()
		T.throws(function()
			Zones.maxSize(0)
		end, "zone must be")
		T.throws(function()
			Zones.maxSize(51)
		end, "zone must be")
		T.throws(function()
			Zones.barrierPrice(1.5)
		end, "zone must be")
		T.throws(function()
			Zones.ballValue(0 / 0)
		end, "size must be")
		T.throws(function()
			Zones.ballValue(-1)
		end, "size must be")
		T.equal(Zones.isZone("1"), false)
	end)
end)

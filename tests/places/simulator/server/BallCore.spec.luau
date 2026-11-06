--!strict
-- BallCore (issue #33, ADR 0002): zone optics from the size fraction, growth counted only up
-- to MaxCountedSpeed, stepped resizes and the out-of-reach leash, against the real Config.

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local BallConfig = require("../../../../src/shared/Config/Ball")
local BallCore = require("../../../../src/places/simulator/server/BallService/BallCore")

local core = BallCore.new(BallConfig :: any, E.Config.Zones :: any, E.Zones.zoneOptics)

return T.suite("Simulator BallCore (7.3)", function(test)
	test("7.3 optics: zone 1 ball goes from 40 % to 100 % of 4 studs", function()
		T.near(core.visualDiameter(1, 0), 1.6, 1e-9, "start")
		T.near(core.visualDiameter(1, 0.5), 2.8, 1e-9, "half")
		T.near(core.visualDiameter(1, 1), 4, 1e-9, "full")
	end)

	test("7.3 optics: 4 + 0.94 * (zone - 1) studs, Visual Cap 50", function()
		for zone = 1, E.Zones.zoneCount do
			local optics = math.min(4 + 0.94 * (zone - 1), 50)
			T.near(core.visualDiameter(zone, 1), optics, 1e-9, `zone {zone} full`)
			T.near(core.visualDiameter(zone, 0), optics * 0.4, 1e-9, `zone {zone} start`)
			T.isTrue(core.visualDiameter(zone, 1) <= E.Config.Zones.VisualCap, `zone {zone} capped`)
		end
	end)

	test("optics grow monotonically with the fraction", function()
		local previous = 0
		for i = 0, 20 do
			local diameter = core.visualDiameter(10, i / 20)
			T.isTrue(diameter > previous, `step {i}`)
			previous = diameter
		end
	end)

	test("invalid fractions and zones are errors", function()
		T.throws(function()
			core.visualDiameter(1, 1.5)
		end, "fraction")
		T.throws(function()
			core.visualDiameter(1, 0 / 0)
		end, "fraction")
		T.throws(function()
			core.visualDiameter(0, 0.5)
		end, "zone must be")
		T.equal(core.isFraction("0.5"), false)
		T.equal(core.isFraction(-0.01), false)
		T.equal(core.isFraction(0), true)
		T.equal(core.isFraction(1), true)
	end)

	test("7.3 growth counts speed only up to MaxCountedSpeed", function()
		local dt = BallConfig.SampleInterval
		T.near(core.countedDistance(1, dt), 1, 1e-9, "10 studs/s counts fully")
		T.near(core.countedDistance(4, dt), BallConfig.MaxCountedSpeed * dt, 1e-9, "40 studs/s capped")
		T.near(core.countedDistance(1000, dt), BallConfig.MaxCountedSpeed * dt, 1e-9, "teleport capped")
		T.equal(core.countedDistance(BallConfig.MinDistancePerSample / 2, dt), 0, "jitter")
		T.equal(core.countedDistance(1, 0), 0, "no time passed")
		T.equal(core.countedDistance(0 / 0, dt), 0, "NaN")
		T.equal(core.countedDistance(math.huge, dt), 0, "inf")
	end)

	test("the ball grows only on the ground and stays within 0..1", function()
		local dt = BallConfig.SampleInterval
		T.equal(core.grow(0.2, 1, dt, false), 0.2, "airborne")
		T.near(core.grow(0.2, 1, dt, true), 0.2 + BallConfig.PrototypeFractionPerStud, 1e-12, "rolled 1 stud")
		T.equal(core.grow(0.999, 2, dt, true), 1, "clamped at 1")
	end)

	test("the base walk speed is counted fully; upgraded speed is capped", function()
		T.isTrue(BallConfig.WalkSpeed < BallConfig.MaxCountedSpeed, "WalkSpeed < MaxCountedSpeed")
		local dt = BallConfig.SampleInterval
		local base = core.grow(0, BallConfig.WalkSpeed * dt, dt, true)
		local upgraded = core.grow(0, 40 * dt, dt, true)
		T.near(base, BallConfig.WalkSpeed * dt * BallConfig.PrototypeFractionPerStud, 1e-12, "base")
		T.near(upgraded, BallConfig.MaxCountedSpeed * dt * BallConfig.PrototypeFractionPerStud, 1e-12, "capped")
	end)

	test("resizes come in steps, with the last step at the ends of the range", function()
		T.equal(core.shouldResize(2, 2.01, 0.3), false, "below the step")
		T.equal(core.shouldResize(2, 2 * (1 + BallConfig.ResizeStepFraction), 0.3), true, "one step")
		T.equal(core.shouldResize(3.97, 4, 1), true, "full ball gets its last bit")
		T.equal(core.shouldResize(4, 4, 1), false, "already there")
		T.equal(core.shouldResize(2, 1.6, 0), true, "reset to start shrinks")
	end)

	test("growing through a whole zone takes few resizes", function()
		local resizes = 0
		local current = core.visualDiameter(1, 0)
		local fraction = 0
		local dt = BallConfig.SampleInterval
		local samples = 0
		while fraction < 1 do
			fraction = core.grow(fraction, BallConfig.WalkSpeed * dt, dt, true)
			samples += 1
			local target = core.visualDiameter(1, fraction)
			if core.shouldResize(current, target, fraction) then
				current = target
				resizes += 1
			end
		end
		T.near(current, 4, 1e-9, "ends at the full zone optics")
		T.isTrue(resizes <= samples / 4, `{resizes} resizes in {samples} samples`)
	end)

	test("leash: out of reach beyond the hold distance plus LeashDistance, for LeashTime", function()
		local diameter = 10
		local reach = diameter / 2 + BallConfig.HoldGap + BallConfig.LeashDistance
		T.equal(core.holdDistance(diameter), diameter / 2 + BallConfig.HoldGap)
		T.equal(core.isOutOfReach(reach - 0.1, diameter), false)
		T.equal(core.isOutOfReach(reach + 0.1, diameter), true)
		T.equal(core.leashExpired(BallConfig.LeashTime - 0.01), false)
		T.equal(core.leashExpired(BallConfig.LeashTime), true)
	end)
end)

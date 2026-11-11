--!strict
-- GrowthRules (issue #34, concept 7.4, ADR 0002): metres against the fraction, the 40 s
-- calibration, surfaces, character range, collision loss and knock-over, on the real Config.

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local SeededRandom = require("../../../helpers/SeededRandom")
local BallConfig = require("../../../../src/shared/Config/Ball")
local GrowthRules = require("../../../../src/places/simulator/server/BallService/GrowthRules")
local GrowthModifiers = require("../../../../src/places/simulator/server/BallService/GrowthModifiers")

local rules = GrowthRules.new(BallConfig :: any, E.Zones.maxSize)
local modifiers = GrowthModifiers.new(E.Upgrades.effect)
local surfaces = BallConfig.Surfaces

local TOLERANCE = 3 -- AC1: 40 s +- 3 s
local PER_STUD = rules.fractionPerStud(modifiers.timeToMax(nil))

local function facts(overrides: { [string]: any }): any
	local base = {
		paused = false,
		atMax = false,
		hasCharacter = true,
		inRange = true,
		grounded = true,
		surface = surfaces.Snow,
		onTrack = false,
		distance = 1,
	}
	for key, value in overrides do
		(base :: any)[key] = value
	end
	return base
end

-- Server samples of a client-owned ball. The ball really moves at `speed`, but a position only
-- reaches the server in packets of about 20 per second with jitter, and `stallsAt` fractions
-- pause the packets for `stall` seconds (a server resize of the owned part).
local function timeToMaximum(speed: number, multiplier: number, limit: (number, number) -> number): number
	local random = SeededRandom.new(34)
	local dt = BallConfig.SampleInterval
	local fraction, now, seen, previous = 0, 0, 0, 0
	local nextPacket = 0
	local stallUntil = 0
	local nextStallAt = 0.02
	while fraction < 1 and now < 200 do
		now += dt
		while nextPacket <= now do
			if nextPacket >= stallUntil then
				seen = nextPacket * speed
			end
			nextPacket += 0.05 + (random.next() - 0.5) * 0.04
		end
		local distance = seen - previous
		previous = seen
		fraction = rules.grow(fraction, limit(distance, dt), PER_STUD, multiplier)
		if fraction >= nextStallAt then
			nextStallAt += 0.02
			stallUntil = now + 0.15
		end
	end
	return now
end

local function creditLimit(): (number, number) -> number
	local credit = 0
	return function(distance: number, dt: number): number
		local counted, newCredit = rules.consumeCredit(credit, distance, dt)
		credit = newCredit
		return counted
	end
end

return T.suite("Simulator GrowthRules (7.4)", function(test)
	test("7.4 size: 10 % of the zone maximum at fraction 0, the maximum at 1, linear between", function()
		T.near(rules.sizeMetres(1, 0), 0.2, 1e-9, "zone 1 start")
		T.near(rules.sizeMetres(1, 1), 2, 1e-9, "zone 1 max")
		T.near(rules.sizeMetres(1, 0.5), 1.1, 1e-9, "zone 1 half")
		for zone = 1, E.Zones.zoneCount do
			T.near(rules.sizeMetres(zone, 0), E.Zones.maxSize(zone) * 0.1, 1e-6, `zone {zone} start`)
			T.near(rules.sizeMetres(zone, 1), E.Zones.maxSize(zone), 1e-6, `zone {zone} max`)
			T.near(rules.fractionForSize(zone, rules.sizeMetres(zone, 0.37)), 0.37, 1e-9, `zone {zone} round trip`)
		end
	end)

	test("AC6: the size text is metres up to 999.9 m and kilometres above", function()
		T.equal(E.NumberFormat.size(rules.sizeMetres(1, 0)), "0.2 m")
		T.equal(E.NumberFormat.size(4.71), "4.7 m")
		T.equal(E.NumberFormat.size(999.94), "999.9 m")
		T.equal(E.NumberFormat.size(1000), "1.0 km")
		T.equal(E.NumberFormat.size(1250), "1.2 km")
	end)

	test("the seam returns the level-0 upgrade values until UpgradeService exists", function()
		local seam = GrowthModifiers.new(E.Upgrades.effect)
		T.equal(seam.timeToMax(nil), E.Config.Upgrades.Definitions.growth.Start)
		T.equal(seam.collisionLoss(nil), E.Config.Upgrades.Definitions.stability.Start)
		T.equal(seam.timeToMax(nil), 40)
		T.near(seam.collisionLoss(nil), 0.1, 1e-12)
	end)

	test("7.4: Growth level 100 is 8 s and Stability level 100 is 2 %", function()
		local seam = GrowthModifiers.new(E.Upgrades.effect)
		seam.setLevelSource(function(): number
			return E.Upgrades.maxLevel
		end)
		T.near(seam.timeToMax(nil), 8, 1e-9)
		T.near(seam.collisionLoss(nil), 0.02, 1e-9)
	end)

	test("AC1: a steady ball at walk speed reaches the maximum in 40 s", function()
		local dt = BallConfig.SampleInterval
		local fraction, credit, seconds = 0, 0, 0
		while fraction < 1 do
			local counted
			counted, credit = rules.consumeCredit(credit, BallConfig.WalkSpeed * dt, dt)
			fraction = rules.grow(fraction, counted, PER_STUD, 1)
			seconds += dt
		end
		T.near(seconds, 40, dt * 2)
	end)

	test("AC1: uneven packets and resize stalls stay within 40 s +- 3 s", function()
		local seconds = timeToMaximum(BallConfig.WalkSpeed, 1, creditLimit())
		T.near(seconds, 40, TOLERANCE, `took {seconds} s`)
	end)

	test("calibration: a limit per sample loses the distance that the credit keeps", function()
		local perSample = function(distance: number, dt: number): number
			if distance < BallConfig.MinDistancePerSample then
				return 0
			end
			return math.min(distance, BallConfig.MaxCountedSpeed * dt)
		end
		local old = timeToMaximum(BallConfig.WalkSpeed, 1, perSample)
		local new = timeToMaximum(BallConfig.WalkSpeed, 1, creditLimit())
		T.isTrue(old > new + TOLERANCE, `per sample {old} s, credit {new} s`)
	end)

	test("AC2: deep snow takes half as long, with the same packets", function()
		local normal = timeToMaximum(BallConfig.WalkSpeed, 1, creditLimit())
		local deep = timeToMaximum(BallConfig.WalkSpeed, rules.surfaceMultiplier(surfaces.DeepSnow), creditLimit())
		T.near(deep, normal / 2, 1.5, `deep {deep} s, normal {normal} s`)
	end)

	test("AC7: growth is proportional to speed and stops rising at MaxCountedSpeed", function()
		local dt = BallConfig.SampleInterval
		local function rate(speed: number): number
			local credit, total = 0, 0
			for _ = 1, 1000 do
				local counted
				counted, credit = rules.consumeCredit(credit, speed * dt, dt)
				total += counted
			end
			return total / (1000 * dt)
		end
		T.near(rate(8), 8, 0.02, "half speed")
		T.near(rate(BallConfig.WalkSpeed), BallConfig.WalkSpeed, 0.02, "base")
		T.near(rate(BallConfig.MaxCountedSpeed), BallConfig.MaxCountedSpeed, 0.02, "the limit")
		T.near(rate(40), BallConfig.MaxCountedSpeed, 0.02, "faster counts at the limit")
		T.near(rate(1000), BallConfig.MaxCountedSpeed, 0.02, "teleporting counts at the limit")
	end)

	test("the credit keeps a single burst bounded and rejects nonsense", function()
		local window = BallConfig.MaxCountedSpeed * BallConfig.CountedBurstWindow
		local counted, credit = rules.consumeCredit(window, 1e6, BallConfig.SampleInterval)
		T.near(counted, window, 1e-9, "one teleport counts one window at most")
		T.near(credit, 0, 1e-9, "and empties the credit")
		T.equal((rules.consumeCredit(5, BallConfig.MinDistancePerSample / 2, 0.1)), 0, "jitter")
		T.equal((rules.consumeCredit(5, 1, 0)), 0, "no time passed")
		T.equal((rules.consumeCredit(5, 0 / 0, 0.1)), 0, "NaN distance")
		T.equal((rules.consumeCredit(5, math.huge, 0.1)), 0, "infinite distance")
		local _, kept = rules.consumeCredit(window, 0, 100)
		T.near(kept, window, 1e-9, "standing still does not save up more than one window")
	end)

	test("7.4 surfaces: deep snow doubles, ice, grass and untagged ground give nothing", function()
		T.equal(rules.surfaceMultiplier(surfaces.Snow), 1)
		T.equal(rules.surfaceMultiplier(surfaces.DeepSnow), 2)
		T.equal(rules.surfaceMultiplier(surfaces.Ice), 0)
		T.equal(rules.surfaceMultiplier(surfaces.Grass), 0)
		T.equal(rules.surfaceMultiplier("None"), 0)
		T.equal(rules.surfaceMultiplier("Air"), 0)
	end)

	test("AC4a: the range is measured from the ball's edge, the same for every size", function()
		local range = BallConfig.GrowthRange
		for _, diameter in { 1.6, 4, 12, 50 } do
			local radius = diameter / 2
			local height = 3 - radius -- root part height above the ground, against the ball centre
			T.equal(rules.inGrowthRange(radius + BallConfig.HoldGap, height, diameter), true, `holding {diameter}`)
			T.equal(rules.inGrowthRange(radius + range - 0.01, height, diameter), true, `edge of range {diameter}`)
			T.equal(rules.inGrowthRange(radius + range + 0.01, height, diameter), false, `out of range {diameter}`)
		end
	end)

	test("AC4b: the range is well beyond the hold gap", function()
		T.isTrue(BallConfig.GrowthRange >= BallConfig.HoldGap * 3, "room for turns and lag")
	end)

	test("AC4a: a character far above the ball does not count", function()
		T.equal(rules.inGrowthRange(0, 4 + BallConfig.GrowthVerticalRange + 1, 8), false)
		T.equal(rules.inGrowthRange(0 / 0, 0, 8), false, "NaN")
	end)

	test("AC4: why a sample counts or not, in order", function()
		T.equal(rules.growthBlock(facts({})), nil, "pushing on snow")
		T.equal(rules.growthBlock(facts({ surface = surfaces.DeepSnow })), nil, "deep snow")
		T.equal(rules.growthBlock(facts({ paused = true })), "Paused")
		T.equal(rules.growthBlock(facts({ atMax = true })), "AtMax")
		T.equal(rules.growthBlock(facts({ hasCharacter = false })), "NoCharacter", "AC4d")
		T.equal(rules.growthBlock(facts({ inRange = false })), "TooFar", "AC4")
		T.equal(rules.growthBlock(facts({ grounded = false })), "Airborne")
		T.equal(rules.growthBlock(facts({ surface = surfaces.Ice })), "NoSnow")
		T.equal(rules.growthBlock(facts({ surface = surfaces.Grass })), "NoSnow")
		T.equal(rules.growthBlock(facts({ onTrack = true })), "Track")
		T.equal(rules.growthBlock(facts({ distance = 0 })), "NotRolling")
		T.equal(rules.growthBlock(facts({ distance = 0 / 0 })), "NotRolling")
	end)

	test("AC4c: rolling on without a push still counts while the character stays in range", function()
		-- Nothing asks whether the character moves: only the ball's movement and the range do.
		T.equal(rules.growthBlock(facts({ distance = 0.5, inRange = true })), nil)
	end)

	test("AC3: a collision costs 10 % of the current size in metres", function()
		local loss = modifiers.collisionLoss(nil)
		local before = rules.sizeMetres(1, 0.5)
		local fraction, lost = rules.collide(1, 0.5, loss)
		T.near(rules.sizeMetres(1, fraction), before * 0.9, 1e-9, "size after")
		T.near(lost, before * 0.1, 1e-9, "metres lost")
	end)

	test("7.4: a collision never goes below the start size", function()
		local fraction, lost = rules.collide(1, 0, 0.1)
		T.equal(fraction, 0, "stays at the start size")
		T.equal(lost, 0, "and loses nothing")
		local small = rules.fractionForSize(1, 0.21)
		local after = rules.collide(1, small, 0.1)
		T.near(rules.sizeMetres(1, after), 0.2, 1e-9, "clamped at the start size")
	end)

	test("7.4 knock-over: at least 3x the obstacle's size, only with a valid size", function()
		T.equal(rules.canKnockOver(3, 1), true, "exactly 3x")
		T.equal(rules.canKnockOver(2.99, 1), false, "just below")
		T.equal(rules.canKnockOver(50, nil), false, "large obstacle: no attribute")
		T.equal(rules.canKnockOver(50, "1"), false, "wrong type")
		T.equal(rules.canKnockOver(50, 0), false, "zero")
		T.equal(rules.canKnockOver(50, 0 / 0), false, "NaN")
	end)
end)

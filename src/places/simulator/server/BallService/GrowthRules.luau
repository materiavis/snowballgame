--!strict
-- Pure growth rules for BallService (concept 7.4, ADR 0002): metres against the size fraction,
-- what a rolled stud is worth, whether growth counts at all and what a collision costs. No
-- Instances, so `lune run tests` loads it; BallService/init.luau binds it to Config.Ball and
-- Formulas.Zones.maxSize.
--
-- The fraction 0..1 stays the single interface the optics read. Fraction 0 is the start size,
-- fraction 1 the maximum of the zone, and metres are linear between them, so a constant rate
-- of fraction is also the constant rate of metres that "40 s from start to maximum" asks for.

export type GrowthConfig = {
	WalkSpeed: number,
	MaxCountedSpeed: number,
	MinDistancePerSample: number,
	CountedBurstWindow: number,
	StartSizeFraction: number,
	DeepSnowGrowthMultiplier: number,
	KnockOverSizeRatio: number,
	GrowthRange: number,
	GrowthVerticalRange: number,
	Surfaces: { Snow: string, DeepSnow: string, Ice: string, Grass: string },
}

-- Why a sample did not grow the ball. Published in Studio for the playtester.
export type GrowthBlock = "Paused" | "AtMax" | "NoCharacter" | "TooFar" | "Airborne" | "NoSnow" | "Track" | "NotRolling"

export type GrowthFacts = {
	paused: boolean,
	atMax: boolean,
	hasCharacter: boolean,
	inRange: boolean,
	grounded: boolean,
	surface: string,
	onTrack: boolean,
	distance: number,
}

export type GrowthRules = {
	startSize: (zone: number) -> number,
	sizeMetres: (zone: number, fraction: number) -> number,
	fractionForSize: (zone: number, metres: number) -> number,
	fractionPerStud: (timeToMax: number) -> number,
	surfaceMultiplier: (surface: string) -> number,
	consumeCredit: (credit: number, distance: number, elapsed: number) -> (number, number),
	inGrowthRange: (horizontal: number, vertical: number, diameter: number) -> boolean,
	growthBlock: (facts: GrowthFacts) -> GrowthBlock?,
	grow: (fraction: number, counted: number, perStud: number, multiplier: number) -> number,
	collide: (zone: number, fraction: number, loss: number) -> (number, number),
	canKnockOver: (diameter: number, obstacleSize: any) -> boolean,
}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local GrowthRulesModule = {}

-- `maxSize(zone)` is Formulas.Zones.maxSize: the zone's maximum in metres.
function GrowthRulesModule.new(config: GrowthConfig, maxSize: (zone: number) -> number): GrowthRules
	local surfaces = config.Surfaces

	local function startSize(zone: number): number
		return maxSize(zone) * config.StartSizeFraction
	end

	local function sizeMetres(zone: number, fraction: number): number
		local start = startSize(zone)
		return start + (maxSize(zone) - start) * fraction
	end

	local function fractionForSize(zone: number, metres: number): number
		local start = startSize(zone)
		return math.clamp((metres - start) / (maxSize(zone) - start), 0, 1)
	end

	-- Q-G (ADR 0003): the time to the maximum is measured at the unupgraded pushing speed, so a
	-- full zone is timeToMax * WalkSpeed studs of normal snow, at every zone and ball size.
	local function fractionPerStud(timeToMax: number): number
		return 1 / (timeToMax * config.WalkSpeed)
	end

	local function surfaceMultiplier(surface: string): number
		if surface == surfaces.Snow then
			return 1
		elseif surface == surfaces.DeepSnow then
			return config.DeepSnowGrowthMultiplier
		end
		return 0
	end

	-- Concept 7.3: speed counts only up to MaxCountedSpeed. Returns (counted studs, new credit).
	-- A credit instead of a limit per sample: a sample that saw no new packet and the next one
	-- that saw two are together normal walking, and only the sum may be judged. Over any span
	-- the total stays at most MaxCountedSpeed * (span + CountedBurstWindow), however the client
	-- times its packets.
	local function consumeCredit(credit: number, distance: number, elapsed: number): (number, number)
		if not isFinite(elapsed) or elapsed <= 0 then
			return 0, credit
		end
		local limit = config.MaxCountedSpeed * config.CountedBurstWindow
		local refilled = math.min(credit + config.MaxCountedSpeed * elapsed, limit)
		if not isFinite(distance) or distance < config.MinDistancePerSample then
			return 0, refilled
		end
		local counted = math.min(distance, refilled)
		return counted, refilled - counted
	end

	-- 7.4 "character directly at the ball", AC4a. Measured to the edge of the ball on the
	-- ground plane: a character beside a big ball stands level with its lowest point, where
	-- the true distance to the sphere grows with the radius and no single range would fit.
	local function inGrowthRange(horizontal: number, vertical: number, diameter: number): boolean
		if not isFinite(horizontal) or not isFinite(vertical) or not isFinite(diameter) then
			return false
		end
		local radius = diameter / 2
		return horizontal - radius <= config.GrowthRange and math.abs(vertical) <= radius + config.GrowthVerticalRange
	end

	-- nil when this sample counts; otherwise the first reason it does not.
	local function growthBlock(facts: GrowthFacts): GrowthBlock?
		if facts.paused then
			return "Paused"
		elseif facts.atMax then
			return "AtMax"
		elseif not facts.hasCharacter then
			return "NoCharacter"
		elseif not facts.inRange then
			return "TooFar"
		elseif not facts.grounded then
			return "Airborne"
		elseif surfaceMultiplier(facts.surface) <= 0 then
			return "NoSnow"
		elseif facts.onTrack then
			return "Track"
		elseif not isFinite(facts.distance) or facts.distance < config.MinDistancePerSample then
			return "NotRolling"
		end
		return nil
	end

	local function grow(fraction: number, counted: number, perStud: number, multiplier: number): number
		return math.clamp(fraction + counted * perStud * multiplier, 0, 1)
	end

	-- Concept 7.4: a collision costs a share of the current size in metres, never below the
	-- start size. Returns (new fraction, metres lost).
	local function collide(zone: number, fraction: number, loss: number): (number, number)
		local size = sizeMetres(zone, fraction)
		local reduced = math.max(size * (1 - loss), startSize(zone))
		return fractionForSize(zone, reduced), size - reduced
	end

	-- `obstacleSize` is the obstacle's attribute: nil or nonsense means it can never be knocked
	-- over, so a mistyped attribute makes a solid obstacle, not one that vanishes.
	local function canKnockOver(diameter: number, obstacleSize: any): boolean
		return isFinite(obstacleSize) and obstacleSize > 0 and diameter >= config.KnockOverSizeRatio * obstacleSize
	end

	return table.freeze({
		startSize = startSize,
		sizeMetres = sizeMetres,
		fractionForSize = fractionForSize,
		fractionPerStud = fractionPerStud,
		surfaceMultiplier = surfaceMultiplier,
		consumeCredit = consumeCredit,
		inGrowthRange = inGrowthRange,
		growthBlock = growthBlock,
		grow = grow,
		collide = collide,
		canKnockOver = canKnockOver,
	})
end

return table.freeze(GrowthRulesModule)

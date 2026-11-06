--!strict
-- Pure ball rules for BallService (concept 7.3, ADR 0002): zone optics, interim growth of the
-- size fraction, when to resize the part and when a ball counts as lost. No Instances, so
-- `lune run tests` loads it; BallService/init.luau binds it to Config.Ball and Formulas.Zones.
--
-- The size fraction (0..1 within the current zone) is the single interface the optics read.
-- #34 (7.4) replaces the interim growth that produces it; the optics stay.

export type BallConfig = {
	MaxCountedSpeed: number,
	MinDistancePerSample: number,
	PrototypeFractionPerStud: number,
	ResizeStepFraction: number,
	HoldGap: number,
	LeashDistance: number,
	LeashTime: number,
}

export type OpticsConfig = {
	OpticsStartFraction: number,
}

export type BallCore = {
	isFraction: (value: any) -> boolean,
	visualDiameter: (zone: number, fraction: number) -> number,
	countedDistance: (distance: number, elapsed: number) -> number,
	grow: (fraction: number, distance: number, elapsed: number, grounded: boolean) -> number,
	shouldResize: (currentDiameter: number, targetDiameter: number, fraction: number) -> boolean,
	holdDistance: (diameter: number) -> number,
	isOutOfReach: (horizontalDistance: number, diameter: number) -> boolean,
	leashExpired: (outOfReachFor: number) -> boolean,
}

-- Studs of diameter below which a resize is not worth a physics change at the bounds.
local RESIZE_EPSILON = 1e-3

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local BallCoreModule = {}

-- `zoneOptics(zone)` is Formulas.Zones.zoneOptics: full-ball diameter of a zone in studs,
-- already capped at Config.Zones.VisualCap. It errors on an invalid zone.
function BallCoreModule.new(config: BallConfig, optics: OpticsConfig, zoneOptics: (zone: number) -> number): BallCore
	local function isFraction(value: any): boolean
		return isFinite(value) and value >= 0 and value <= 1
	end

	-- Concept 7.3: inside a zone the ball grows visually from OpticsStartFraction to 100 % of
	-- the zone optics.
	local function visualDiameter(zone: number, fraction: number): number
		if not isFraction(fraction) then
			error(`BallCore: fraction must be a number 0..1, got {tostring(fraction)}`, 2)
		end
		local start = optics.OpticsStartFraction
		return zoneOptics(zone) * (start + (1 - start) * fraction)
	end

	-- Concept 7.3: growth counts speed only up to MaxCountedSpeed. Faster movement (upgrades,
	-- teleports, an exploiting owner) is counted at that speed, never more.
	local function countedDistance(distance: number, elapsed: number): number
		if not isFinite(distance) or not isFinite(elapsed) or elapsed <= 0 then
			return 0
		end
		if distance < config.MinDistancePerSample then
			return 0
		end
		return math.min(distance, config.MaxCountedSpeed * elapsed)
	end

	-- `grounded` means both samples of this step were on the ground.
	local function grow(fraction: number, distance: number, elapsed: number, grounded: boolean): number
		if not grounded then
			return fraction
		end
		local grown = fraction + countedDistance(distance, elapsed) * config.PrototypeFractionPerStud
		return math.clamp(grown, 0, 1)
	end

	-- Resizing in steps keeps the solver from seeing a new size every sample. At the ends of
	-- the range (0 and 1) the last small step is still applied so the ball reaches its size.
	local function shouldResize(currentDiameter: number, targetDiameter: number, fraction: number): boolean
		local difference = math.abs(targetDiameter - currentDiameter)
		if difference >= currentDiameter * config.ResizeStepFraction then
			return true
		end
		return (fraction <= 0 or fraction >= 1) and difference > RESIZE_EPSILON
	end

	-- Distance from the HumanoidRootPart centre to the ball centre the client holds the ball at.
	local function holdDistance(diameter: number): number
		return diameter / 2 + config.HoldGap
	end

	local function isOutOfReach(horizontalDistance: number, diameter: number): boolean
		return horizontalDistance > holdDistance(diameter) + config.LeashDistance
	end

	local function leashExpired(outOfReachFor: number): boolean
		return outOfReachFor >= config.LeashTime
	end

	return table.freeze({
		isFraction = isFraction,
		visualDiameter = visualDiameter,
		countedDistance = countedDistance,
		grow = grow,
		shouldResize = shouldResize,
		holdDistance = holdDistance,
		isOutOfReach = isOutOfReach,
		leashExpired = leashExpired,
	})
end

return table.freeze(BallCoreModule)

--!strict
-- Zone formulas (concept 7.3, 7.6, 8.3). Pure: the config is passed to new(), so `lune run
-- tests` loads this file; Formulas/init.luau binds it to Config.Zones in Roblox.
-- Values are exact; prices (barrierPrice) are whole coins rounded down (ADR 0007).

export type ZonesConfig = {
	ZoneCount: number,
	ZonesPerWorld: number,
	MaxSizeBase: number,
	SizeGrowth: number,
	BallValueFactor: number,
	StrengthGrowth: number,
	BallsPerBarrierBase: number,
	BallsPerBarrierPerZone: number,
	OpticsBase: number,
	OpticsPerZone: number,
	VisualCap: number,
}

export type Zones = {
	zoneCount: number,
	isZone: (zone: any) -> boolean,
	maxSize: (zone: number) -> number,
	ballValue: (sizeMetres: number) -> number,
	fullBallValue: (zone: number) -> number,
	expectedStrength: (zone: number) -> number,
	ballsPerBarrier: (zone: number) -> number,
	barrierPrice: (zone: number) -> number,
	worldOf: (zone: number) -> number,
	zoneInWorld: (zone: number) -> number,
	isWorldGate: (zone: number) -> boolean,
	zoneOptics: (zone: number) -> number,
}

-- Whole coins, rounded down. The tiny relative nudge keeps a product that should be whole
-- (79.99999999999999 from float maths) from losing a coin; it is far below one coin.
local function wholeCoins(value: number): number
	return math.floor(value * (1 + 1e-12))
end

local ZonesFormulas = {}

function ZonesFormulas.new(config: ZonesConfig): Zones
	local function isZone(zone: any): boolean
		return type(zone) == "number" and zone % 1 == 0 and zone >= 1 and zone <= config.ZoneCount
	end

	local function check(zone: number)
		if not isZone(zone) then
			error(`Formulas.Zones: zone must be a whole number 1..{config.ZoneCount}, got {tostring(zone)}`, 3)
		end
	end

	local function maxSize(zone: number): number
		check(zone)
		return config.MaxSizeBase * config.SizeGrowth ^ (zone - 1)
	end

	-- Any size, not only a full ball: selling before the maximum uses the same formula (7.5).
	local function ballValue(sizeMetres: number): number
		if type(sizeMetres) ~= "number" or sizeMetres ~= sizeMetres or sizeMetres < 0 or sizeMetres == math.huge then
			error(`Formulas.Zones: size must be a finite number >= 0, got {tostring(sizeMetres)}`, 2)
		end
		return config.BallValueFactor * sizeMetres ^ 3
	end

	local function fullBallValue(zone: number): number
		return ballValue(maxSize(zone))
	end

	local function expectedStrength(zone: number): number
		check(zone)
		return config.StrengthGrowth ^ (zone - 1)
	end

	local function ballsPerBarrier(zone: number): number
		check(zone)
		return config.BallsPerBarrierBase + config.BallsPerBarrierPerZone * zone
	end

	-- Price of the barrier at the end of `zone` (opens zone + 1). World gates cost the same.
	-- Whole coins, rounded down, so it can be spent through CurrencyService.
	local function barrierPrice(zone: number): number
		return wholeCoins(fullBallValue(zone) * ballsPerBarrier(zone) * expectedStrength(zone))
	end

	local function worldOf(zone: number): number
		check(zone)
		return (zone - 1) // config.ZonesPerWorld + 1
	end

	local function zoneInWorld(zone: number): number
		check(zone)
		return (zone - 1) % config.ZonesPerWorld + 1
	end

	-- The last zone of a world (10, 20, ...) ends in a world gate instead of a barrier, except
	-- the very last zone.
	local function isWorldGate(zone: number): boolean
		return zoneInWorld(zone) == config.ZonesPerWorld and zone < config.ZoneCount
	end

	-- Studs: 4 in zone 1 up to 50 in zone 50, never above the visual cap (7.3).
	local function zoneOptics(zone: number): number
		check(zone)
		return math.min(config.OpticsBase + config.OpticsPerZone * (zone - 1), config.VisualCap)
	end

	return table.freeze({
		zoneCount = config.ZoneCount,
		isZone = isZone,
		maxSize = maxSize,
		ballValue = ballValue,
		fullBallValue = fullBallValue,
		expectedStrength = expectedStrength,
		ballsPerBarrier = ballsPerBarrier,
		barrierPrice = barrierPrice,
		worldOf = worldOf,
		zoneInWorld = zoneInWorld,
		isWorldGate = isWorldGate,
		zoneOptics = zoneOptics,
	})
end

return table.freeze(ZonesFormulas)

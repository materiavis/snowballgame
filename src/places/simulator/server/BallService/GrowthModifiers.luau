--!strict
-- The one seam between ball growth and upgrades (concept 7.4, 7.8). Growth time and collision
-- loss are upgrade effects, read through Formulas.Upgrades.effect. UpgradeService (#36) does
-- not exist yet, so every player is at level 0 until it calls setLevelSource.

export type LevelSource = (player: any, upgradeId: string) -> number

export type GrowthModifiers = {
	timeToMax: (player: any) -> number,
	collisionLoss: (player: any) -> number,
	setLevelSource: (source: LevelSource) -> (),
}

local GROWTH_UPGRADE = "growth"
local STABILITY_UPGRADE = "stability"
local NO_UPGRADES = 0

local GrowthModifiersModule = {}

-- `effect(id, level)` is Formulas.Upgrades.effect. It errors on an invalid level.
function GrowthModifiersModule.new(effect: (id: string, level: number) -> number): GrowthModifiers
	local levelOf: LevelSource = function(_player: any, _upgradeId: string): number
		return NO_UPGRADES
	end

	local function timeToMax(player: any): number
		return effect(GROWTH_UPGRADE, levelOf(player, GROWTH_UPGRADE))
	end

	local function collisionLoss(player: any): number
		return effect(STABILITY_UPGRADE, levelOf(player, STABILITY_UPGRADE))
	end

	local function setLevelSource(source: LevelSource)
		levelOf = source
	end

	return table.freeze({
		timeToMax = timeToMax,
		collisionLoss = collisionLoss,
		setLevelSource = setLevelSource,
	})
end

return table.freeze(GrowthModifiersModule)

--!strict
-- Studio-only playtest switches for BallService (ADR 0002 "Playtest hooks"). BallService
-- binds them only in Studio at game.PlaceId == 0. Attributes on `host` (ServerScriptService):
--   BallTargetUserId    number, player the switches act on; 0 = every player
--   BallSetZone         number, idle 0: zone 1..50, applied at once
--   BallSetSizeFraction number, idle -1: size fraction 0..1, applied at once
--   BallGrowthPaused    bool: hold the current size while walking
--   BallRecover         bool: put the ball back in front now
--   BallSimulateCollision bool: one obstacle collision now (respects the protection time)
--   BallMoveCharacterAway number, idle 0: moves the character this many studs away from the
--                       ball, because the hold keeps the ball at the character otherwise
--   BallClearTrack      bool: forget the track of the target
--   BallRecoveryTestGeometry bool: true builds the temporary cliff and hole pier
--                       (TestGeometry, #94), false removes them
-- A value switch runs once and resets itself to idle. Invalid values only warn.

export type Hooks = {
	-- Ball states of the target (0 = all). Opaque to this module.
	targets: (targetUserId: number) -> { any },
	isZone: (value: any) -> boolean,
	isFraction: (value: any) -> boolean,
	zoneCount: number,
	setZone: (state: any, zone: number) -> (),
	setFraction: (state: any, fraction: number) -> (),
	recover: (state: any) -> (),
	setPaused: (paused: boolean) -> (),
	simulateCollision: (state: any) -> (),
	moveCharacterAway: (state: any, studs: number) -> (),
	clearTrack: (state: any) -> (),
	-- Builds (true) or removes (false) the recovery test geometry; returns a log line.
	setTestGeometry: (enabled: boolean) -> string,
	describe: (state: any) -> string, -- "<name> zone=… fraction=… diameter=… metres=…"
}

local TARGET_SWITCH = "BallTargetUserId"
local ZONE_SWITCH = "BallSetZone"
local FRACTION_SWITCH = "BallSetSizeFraction"
local PAUSE_SWITCH = "BallGrowthPaused"
local RECOVER_SWITCH = "BallRecover"
local COLLISION_SWITCH = "BallSimulateCollision"
local MOVE_AWAY_SWITCH = "BallMoveCharacterAway"
local CLEAR_TRACK_SWITCH = "BallClearTrack"
local TEST_GEOMETRY_SWITCH = "BallRecoveryTestGeometry"
local ZONE_IDLE = 0
local FRACTION_IDLE = -1
local MOVE_AWAY_IDLE = 0

local StudioSwitches = {}

function StudioSwitches.bind(host: Instance, hooks: Hooks)
	local function ensure(name: string, default: any)
		if host:GetAttribute(name) == nil then
			host:SetAttribute(name, default)
		end
	end

	local function targets(): { any }
		local target = host:GetAttribute(TARGET_SWITCH)
		return hooks.targets(if type(target) == "number" then target else 0)
	end

	local function bindValue(name: string, idle: any, action: (value: any) -> ())
		ensure(name, idle)
		host:GetAttributeChangedSignal(name):Connect(function()
			local value = host:GetAttribute(name)
			if value == idle or value == nil then
				return
			end
			host:SetAttribute(name, idle)
			action(value)
		end)
	end

	ensure(TARGET_SWITCH, 0)

	bindValue(ZONE_SWITCH, ZONE_IDLE, function(zone)
		if not hooks.isZone(zone) then
			warn(`[BallService] {ZONE_SWITCH}: zone must be a whole number 1..{hooks.zoneCount}, got {zone}`)
			return
		end
		for _, state in targets() do
			hooks.setZone(state, zone)
			print(`[BallService] {ZONE_SWITCH} -> {hooks.describe(state)}`)
		end
	end)

	bindValue(FRACTION_SWITCH, FRACTION_IDLE, function(fraction)
		if not hooks.isFraction(fraction) then
			warn(`[BallService] {FRACTION_SWITCH}: fraction must be a number 0..1, got {fraction}`)
			return
		end
		for _, state in targets() do
			hooks.setFraction(state, fraction)
			print(`[BallService] {FRACTION_SWITCH} -> {hooks.describe(state)}`)
		end
	end)

	bindValue(RECOVER_SWITCH, false, function(value)
		if value == true then
			for _, state in targets() do
				hooks.recover(state)
			end
		end
	end)

	bindValue(COLLISION_SWITCH, false, function(value)
		if value == true then
			for _, state in targets() do
				hooks.simulateCollision(state)
				print(`[BallService] {COLLISION_SWITCH} -> {hooks.describe(state)}`)
			end
		end
	end)

	bindValue(MOVE_AWAY_SWITCH, MOVE_AWAY_IDLE, function(studs)
		if type(studs) ~= "number" or studs <= 0 or studs ~= studs or studs == math.huge then
			warn(`[BallService] {MOVE_AWAY_SWITCH}: studs must be a positive number, got {studs}`)
			return
		end
		for _, state in targets() do
			hooks.moveCharacterAway(state, studs)
			print(`[BallService] {MOVE_AWAY_SWITCH} -> {hooks.describe(state)}`)
		end
	end)

	bindValue(CLEAR_TRACK_SWITCH, false, function(value)
		if value == true then
			for _, state in targets() do
				hooks.clearTrack(state)
				print(`[BallService] {CLEAR_TRACK_SWITCH} -> {hooks.describe(state)}`)
			end
		end
	end)

	ensure(PAUSE_SWITCH, false)
	host:GetAttributeChangedSignal(PAUSE_SWITCH):Connect(function()
		local paused = host:GetAttribute(PAUSE_SWITCH) == true
		hooks.setPaused(paused)
		print(`[BallService] {PAUSE_SWITCH}={paused}`)
	end)

	ensure(TEST_GEOMETRY_SWITCH, false)
	host:GetAttributeChangedSignal(TEST_GEOMETRY_SWITCH):Connect(function()
		local enabled = host:GetAttribute(TEST_GEOMETRY_SWITCH) == true
		print(`[BallService] {TEST_GEOMETRY_SWITCH}={enabled} {hooks.setTestGeometry(enabled)}`)
	end)
end

return table.freeze(StudioSwitches)

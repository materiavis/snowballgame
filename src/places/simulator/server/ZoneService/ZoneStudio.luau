--!strict
-- Studio-only playtest switches and diagnostics for ZoneService (ADR 0014 "Studio playtest
-- support"). ZoneService binds them only in Studio at game.PlaceId == 0. Attributes on `host`
-- (ServerScriptService):
--   ZoneTargetUserId  number, idle 0: player the switches act on; 0 = every player
--   ZoneTestGeometry  bool: true builds the test zones ZoneTest01..06, false removes them
--   ZonePurchase      number, idle 0: runs the unlock of that zone through the remote's path
--   ZoneTeleportTo    number, idle 0: runs a zone teleport through the remote's path
--   ZoneResetUnlocks  bool: true resets the targets to zone 1 only, then back to false
-- A value switch runs once and resets itself to idle. Invalid values reach the normal checks
-- and show up as refusals. Every event is printed and mirrored to player attributes
-- (ZoneAttributes); the map state goes to the host attribute ZoneMapState.

local Players = game:GetService("Players")

export type Hooks = {
	purchase: (player: Player, zone: any) -> (),
	teleport: (player: Player, zone: any) -> (),
	reset: (player: Player) -> (),
	-- Builds (true) or removes (false) the test zones; returns a log line.
	setTestGeometry: (enabled: boolean) -> string,
}

local TARGET_SWITCH = "ZoneTargetUserId"
local GEOMETRY_SWITCH = "ZoneTestGeometry"
local PURCHASE_SWITCH = "ZonePurchase"
local TELEPORT_SWITCH = "ZoneTeleportTo"
local RESET_SWITCH = "ZoneResetUnlocks"
local MAP_STATE = "ZoneMapState"

local ZoneStudio = {}

ZoneStudio.MAP_STATE = MAP_STATE

function ZoneStudio.targets(host: Instance): { Player }
	local target = host:GetAttribute(TARGET_SWITCH)
	if type(target) == "number" and target ~= 0 then
		local player = Players:GetPlayerByUserId(target)
		if player == nil then
			warn(`[ZoneService] {TARGET_SWITCH}: no player with UserId {target}`)
			return {}
		end
		return { player }
	end
	return Players:GetPlayers()
end

function ZoneStudio.bind(host: Instance, hooks: Hooks)
	local function ensure(name: string, default: any)
		if host:GetAttribute(name) == nil then
			host:SetAttribute(name, default)
		end
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

	bindValue(PURCHASE_SWITCH, 0, function(zone)
		for _, player in ZoneStudio.targets(host) do
			task.spawn(hooks.purchase, player, zone)
		end
	end)

	bindValue(TELEPORT_SWITCH, 0, function(zone)
		for _, player in ZoneStudio.targets(host) do
			task.spawn(hooks.teleport, player, zone)
		end
	end)

	bindValue(RESET_SWITCH, false, function(value)
		if value == true then
			for _, player in ZoneStudio.targets(host) do
				hooks.reset(player)
			end
		end
	end)

	ensure(GEOMETRY_SWITCH, false)
	host:GetAttributeChangedSignal(GEOMETRY_SWITCH):Connect(function()
		local enabled = host:GetAttribute(GEOMETRY_SWITCH) == true
		print(`[ZoneService] {GEOMETRY_SWITCH} -> {hooks.setTestGeometry(enabled)}`)
	end)
end

return table.freeze(ZoneStudio)

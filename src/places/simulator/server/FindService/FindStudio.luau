--!strict
-- Studio-only playtest support for FindService (ADR 0016 "Studio playtest support"). FindService
-- binds it only in Studio at game.PlaceId == 0. Switches on `host` (ServerScriptService):
--   FindTargetUserId number, the player the switches act on; 0 = every player
--   FindTestPoints   bool: true puts FindPoint Attachments into the floors of the test zones of
--                    ZoneTestGeometry (Config.Finds.Test); false removes them
--   FindForceRarity  string: every spawn of the targets gets this rarity ("" = off). A rarity the
--                    zone's table does not have (Legendary in zones 1-5) is refused: normal roll
--   FindForceRoll    number: every spawn of the targets uses this roll in [0, 1) (-1 = off)
--   FindRespawnNow   bool, idle false: removes the targets' spawned finds and spawns new ones at
--                    every point now, then resets itself
-- Diagnostics: Config.Finds.DiagnosticAttributes on the Player and on `host`.

local Players = game:GetService("Players")

export type Hooks = {
	-- Applies (or clears) the force of one player.
	setForce: (player: Player, force: any) -> (),
	setTestPoints: (enabled: boolean) -> string,
	respawnNow: (player: Player) -> number,
}

local TARGET = "FindTargetUserId"
local TEST_POINTS = "FindTestPoints"
local FORCE_RARITY = "FindForceRarity"
local FORCE_ROLL = "FindForceRoll"
local RESPAWN_NOW = "FindRespawnNow"
local ROLL_OFF = -1

local FindStudio = {}

FindStudio.Names = table.freeze({
	Target = TARGET,
	TestPoints = TEST_POINTS,
	ForceRarity = FORCE_RARITY,
	ForceRoll = FORCE_ROLL,
	RespawnNow = RESPAWN_NOW,
})

local function default(host: Instance, name: string, value: any)
	if host:GetAttribute(name) == nil then
		host:SetAttribute(name, value)
	end
end

-- The force the switches give, and a problem text for an invalid value. Pure.
function FindStudio.parseForce(rarity: any, roll: any, rarityOrder: { string }): (any, string?)
	local force: { rarity: string?, roll: number? } = {}
	local problems: { string } = {}
	if rarity ~= nil and rarity ~= "" then
		if type(rarity) == "string" and table.find(rarityOrder, rarity) then
			force.rarity = rarity
		else
			table.insert(problems, `{FORCE_RARITY} {tostring(rarity)} is not one of {table.concat(rarityOrder, ", ")}`)
		end
	end
	if roll ~= nil and roll ~= ROLL_OFF then
		if type(roll) == "number" and roll == roll and roll >= 0 and roll < 1 then
			force.roll = roll
		else
			table.insert(problems, `{FORCE_ROLL} {tostring(roll)} is not -1 or a number in [0, 1)`)
		end
	end
	local problem = if #problems > 0 then table.concat(problems, "; ") else nil
	if force.rarity == nil and force.roll == nil then
		return nil, problem
	end
	return force, problem
end

function FindStudio.targets(host: Instance): { Player }
	local target = host:GetAttribute(TARGET)
	if type(target) == "number" and target ~= 0 then
		local player = Players:GetPlayerByUserId(target)
		if player == nil then
			warn(`[FindService] {TARGET}: no player with UserId {target}`)
			return {}
		end
		return { player }
	end
	return Players:GetPlayers()
end

-- The force for `player` from the switches now (nil when off or not a target).
function FindStudio.forceFor(host: Instance, player: Player, rarityOrder: { string }): any
	local target = host:GetAttribute(TARGET)
	if type(target) == "number" and target ~= 0 and target ~= player.UserId then
		return nil
	end
	return (FindStudio.parseForce(host:GetAttribute(FORCE_RARITY), host:GetAttribute(FORCE_ROLL), rarityOrder))
end

function FindStudio.bind(host: Instance, hooks: Hooks, rarityOrder: { string })
	default(host, TARGET, 0)
	default(host, TEST_POINTS, false)
	default(host, FORCE_RARITY, "")
	default(host, FORCE_ROLL, ROLL_OFF)
	default(host, RESPAWN_NOW, false)

	local function applyForce()
		local force, problem =
			FindStudio.parseForce(host:GetAttribute(FORCE_RARITY), host:GetAttribute(FORCE_ROLL), rarityOrder)
		if problem then
			warn(`[FindService] {problem}; that part is off`)
		end
		for _, player in Players:GetPlayers() do
			hooks.setForce(player, FindStudio.forceFor(host, player, rarityOrder))
		end
		local text = if force then `rarity={tostring(force.rarity)} roll={tostring(force.roll)}` else "off"
		print(`[FindService] force {text} for {tostring(host:GetAttribute(TARGET))}`)
	end
	host:GetAttributeChangedSignal(FORCE_RARITY):Connect(applyForce)
	host:GetAttributeChangedSignal(FORCE_ROLL):Connect(applyForce)
	host:GetAttributeChangedSignal(TARGET):Connect(applyForce)

	host:GetAttributeChangedSignal(TEST_POINTS):Connect(function()
		local enabled = host:GetAttribute(TEST_POINTS) == true
		print(`[FindService] {TEST_POINTS} {enabled} -> {hooks.setTestPoints(enabled)}`)
	end)

	host:GetAttributeChangedSignal(RESPAWN_NOW):Connect(function()
		if host:GetAttribute(RESPAWN_NOW) ~= true then
			return
		end
		host:SetAttribute(RESPAWN_NOW, false)
		for _, player in FindStudio.targets(host) do
			print(`[FindService] {RESPAWN_NOW} {player.Name} ({player.UserId}) spawned {hooks.respawnNow(player)}`)
		end
	end)
end

-- Test points in the floors of ZoneTest01..: returns a log line. `remove` only takes them out.
function FindStudio.setTestPoints(
	map: Instance?,
	mapConfig: any,
	findsConfig: any,
	tag: string,
	enabled: boolean,
	addTag: (instance: Instance, tag: string) -> ()
): string
	if map == nil then
		return `no Workspace.{mapConfig.FolderName}`
	end
	local zoneTest = mapConfig.ZoneTest
	local test = findsConfig.Test
	local removed, added, zones = 0, 0, 0
	for zone = 1, zoneTest.Count do
		local area = map:FindFirstChild(string.format("%s%02d", zoneTest.AreaPrefix, zone))
		local floor = area and area:FindFirstChildWhichIsA("BasePart")
		if floor then
			for _, child in floor:GetChildren() do
				if child:IsA("Attachment") and string.sub(child.Name, 1, #test.NamePrefix) == test.NamePrefix then
					child:Destroy()
					removed += 1
				end
			end
			if enabled then
				zones += 1
				local startX = zoneTest.Origin[1] + (zone - 1) * zoneTest.Length
				for index, offset in test.Points do
					local point = Instance.new("Attachment")
					point.Name = `{test.NamePrefix}{index}`
					point.Parent = floor
					point.WorldPosition =
						Vector3.new(startX + offset[1], zoneTest.Origin[2], zoneTest.Origin[3] + offset[2])
					addTag(point, tag)
					added += 1
				end
			end
		end
	end
	if not enabled then
		return `removed {removed} test points`
	end
	if zones == 0 then
		return `not built: no {zoneTest.AreaPrefix}NN area, set ZoneTestGeometry = true first`
	end
	return `added {added} test points in {zones} test zones (removed {removed} old ones)`
end

local function truncated(list: { string }, limit: number): string
	if #list <= limit then
		return table.concat(list, ",")
	end
	return `{table.concat(list, ",", 1, limit)},…(+{#list - limit})`
end

local function sortedKeys(map: any): { string }
	local keys: { string } = {}
	if type(map) == "table" then
		for key in map do
			if type(key) == "string" then
				table.insert(keys, key)
			end
		end
	end
	table.sort(keys)
	return keys
end

export type Snapshot = {
	spawned: { any }, -- FindCore.Spawned list
	ball: { string },
	profile: any,
}

-- Writes the diagnostics of one event and the current lists. Returns the log text.
function FindStudio.writeDiagnostics(player: Player, names: any, event: any, snapshot: Snapshot, now: number): string
	local kind = event.kind
	local where = `slot {tostring(event.slot)} zone {tostring(event.zone)}`
	local text: string
	if kind == "Spawn" then
		local how = if event.forced == "Rarity"
			then "forced rarity"
			else `roll={string.format("%.4f", event.roll or -1)}{if event.forced then " forced" else ""}`
		local refused = if event.forceRefused then ` (forced {event.forceRefused} refused in this zone)` else ""
		text = `spawn {where} {event.findId} ({event.rarity}) {how}{refused}`
		player:SetAttribute(names.LastSpawn, text)
		player:SetAttribute(names.LastSpawnSlot, event.slot)
		player:SetAttribute(names.LastSpawnClock, now)
		player:SetAttribute(names.LastRoll, event.roll or -1)
	elseif kind == "Collect" then
		local extra = if event.title then ` title={event.title} new={tostring(event.newTitle)}` else ""
		local problem = if event.collectionProblem then ` NOT RECORDED: {event.collectionProblem}` else ""
		text =
			`pickup {where} {event.findId} ({event.rarity}) value={event.value} first={tostring(event.first)}{extra}{problem}`
		player:SetAttribute(names.LastPickup, text)
		player:SetAttribute(names.LastPickupSlot, event.slot)
		player:SetAttribute(names.LastPickupClock, now)
		player:SetAttribute(names.LastPickupValue, event.value)
		player:SetAttribute(names.LastPickupZone, event.zone)
	elseif kind == "Refused" then
		text = `refused {where} {tostring(event.findId)}: {event.refusal}`
		player:SetAttribute(names.LastRefusal, text)
	else
		text = `{string.lower(kind)} {tostring(event.slot or "")} {tostring(event.reason or "")}`
	end

	local spawnedTexts: { string } = {}
	for _, spawned in snapshot.spawned do
		table.insert(spawnedTexts, `{spawned.slot}:{spawned.zone}:{spawned.findId}`)
	end
	player:SetAttribute(names.Spawned, #snapshot.spawned)
	player:SetAttribute(names.SpawnedList, truncated(spawnedTexts, 60))
	player:SetAttribute(names.BallCount, #snapshot.ball)
	player:SetAttribute(names.BallList, truncated(snapshot.ball, 40))
	local sim = type(snapshot.profile) == "table" and snapshot.profile.sim or nil
	local collection = type(sim) == "table" and type(sim.collection) == "table" and sim.collection.finds or nil
	local found = sortedKeys(collection)
	player:SetAttribute(names.Collection, table.concat(found, ","))
	player:SetAttribute(names.CollectionCount, #found)
	player:SetAttribute(names.Titles, table.concat(sortedKeys(type(sim) == "table" and sim.titles or nil), ","))
	return text
end

return table.freeze(FindStudio)

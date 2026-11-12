--!strict
-- Where each travel intent leads (concept 5.6, ADR 0003 "Places" table, ADR 0010). Pure, no
-- requires: Config.Places and the zone layout are passed in. Destinations come only from the
-- server (current Place, Config, the loaded profile), never from a client or teleport data.

export type Role = "Lobby" | "Simulator" | "Arena"
export type Intent = "Portal" | "WorldGate" | "LobbyButton" | "MatchStart" | "Replay" | "ToLobby" | "LoadFailReturn"

export type Destination = {
	role: Role,
	world: number?, -- Simulator only
	zone: number?, -- Simulator only: the zone the destination will place the player in
	placeId: number, -- 0 = not published yet
	group: boolean, -- travels a whole group onto one server
}

type Rule = { from: { [Role]: boolean }, to: Role, group: boolean }

local RULES: { [string]: Rule } = {
	-- Lobby portal -> Simulator, last visited world and zone (5.6 "Simulator betreten").
	Portal = { from = { Lobby = true }, to = "Simulator", group = false },
	-- World gate at the end of zones 10, 20, 30, 40 -> next world (5.6 "Freischalten").
	WorldGate = { from = { Simulator = true }, to = "Simulator", group = false },
	-- Simulator "Lobby" button.
	LobbyButton = { from = { Simulator = true }, to = "Lobby", group = false },
	-- Matchmaking start (7.14) -> one reserved Arena server for the match.
	MatchStart = { from = { Lobby = true }, to = "Arena", group = true },
	-- "Nochmal" after the match (7.21) -> next reserved Arena server for the group.
	Replay = { from = { Arena = true }, to = "Arena", group = true },
	-- "Zur Lobby" after the match.
	ToLobby = { from = { Arena = true }, to = "Lobby", group = false },
	-- Load failure outside the Lobby (ADR 0003): back to the Lobby after the retries.
	LoadFailReturn = { from = { Simulator = true, Arena = true }, to = "Lobby", group = false },
}

export type Config = {
	places: { Lobby: number, Arena: number, Worlds: { [number]: number } },
	zoneCount: number,
	zonesPerWorld: number,
	role: Role,
	worldIndex: number?,
}

local function isWhole(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value < math.huge
end

local Destinations = {}

Destinations.INTENTS = table.freeze({
	"Portal",
	"WorldGate",
	"LobbyButton",
	"MatchStart",
	"Replay",
	"ToLobby",
	"LoadFailReturn",
})

function Destinations.new(config: Config)
	local places = config.places
	local perWorld = config.zonesPerWorld
	local worldCount = config.zoneCount // perWorld
	local resolver = {}

	local function firstZone(world: number): number
		return (world - 1) * perWorld + 1
	end

	local function worldOf(zone: number): number
		return (zone - 1) // perWorld + 1
	end

	function resolver.isIntent(intent: any): boolean
		return type(intent) == "string" and RULES[intent] ~= nil
	end

	function resolver.isGroup(intent: string): boolean
		local rule = RULES[intent]
		return rule ~= nil and rule.group
	end

	-- Whether this intent may start in the current Place.
	function resolver.allowedHere(intent: string): boolean
		local rule = RULES[intent]
		return rule ~= nil and rule.from[config.role] == true
	end

	-- Returns the destination, or nil and a reason. The third value notes a fallback (an
	-- invalid saved world or zone), so the caller can log it.
	function resolver.resolve(intent: string, profile: any): (Destination?, string?, string?)
		local rule = RULES[intent]
		if rule == nil then
			return nil, "UnknownIntent", nil
		end
		if not rule.from[config.role] then
			return nil, `NotFrom{config.role}`, nil
		end

		if rule.to == "Lobby" then
			return { role = "Lobby", placeId = places.Lobby, group = rule.group }, nil, nil
		elseif rule.to == "Arena" then
			return { role = "Arena", placeId = places.Arena, group = rule.group }, nil, nil
		end

		local world: number, zone: number
		local note: string? = nil
		if intent == "WorldGate" then
			local current = config.worldIndex
			if not isWhole(current) then
				return nil, "NoWorldIndex", nil
			end
			world = (current :: number) + 1
			if world > worldCount then
				return nil, "NoNextWorld", nil
			end
			zone = firstZone(world)
		else
			-- Portal: the last visited world and zone from the profile (ZoneService owns them).
			local sim = if type(profile) == "table" and type(profile.sim) == "table" then profile.sim else nil
			local savedWorld = if sim then sim.lastWorld else nil
			local savedZone = if sim then sim.lastZone else nil
			if isWhole(savedWorld) and savedWorld <= worldCount and places.Worlds[savedWorld] ~= nil then
				world = savedWorld
			else
				world = 1
				note = `saved lastWorld {tostring(savedWorld)} is not a listed world, using World 1`
			end
			if isWhole(savedZone) and savedZone <= config.zoneCount and worldOf(savedZone) == world then
				zone = savedZone
			else
				zone = firstZone(world)
				if note == nil then
					note = `saved lastZone {tostring(savedZone)} is not in World {world}, using zone {zone}`
				end
			end
		end
		local placeId = places.Worlds[world] or 0
		return { role = "Simulator", world = world, zone = zone, placeId = placeId, group = rule.group }, nil, note
	end

	return table.freeze(resolver)
end

return table.freeze(Destinations)

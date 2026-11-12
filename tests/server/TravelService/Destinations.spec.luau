--!strict
-- Where each intent leads from each Place (concept 5.6, ADR 0003 "Places" table, ADR 0010).

local T = require("../../TestKit")
local Destinations = require("../../../src/server/Services/TravelService/Destinations")
local Places = require("../../../src/shared/Config/Places")
local ZonesConfig = require("../../../src/shared/Config/Zones")

local PUBLISHED = { Lobby = 100, Arena = 300, Worlds = { [1] = 201, [2] = 202 } }

local function resolver(role: any, worldIndex: number?, places: any?)
	return Destinations.new({
		places = places or PUBLISHED,
		zoneCount = ZonesConfig.ZoneCount,
		zonesPerWorld = ZonesConfig.ZonesPerWorld,
		role = role,
		worldIndex = worldIndex,
	})
end

local function profile(lastWorld: any, lastZone: any): any
	return { sim = { lastWorld = lastWorld, lastZone = lastZone } }
end

return T.suite("TravelService Destinations", function(test)
	test("each intent starts only from its Place", function()
		local allowed = {
			Lobby = { Portal = true, MatchStart = true },
			Simulator = { WorldGate = true, LobbyButton = true, LoadFailReturn = true },
			Arena = { Replay = true, ToLobby = true, LoadFailReturn = true },
		}
		for role, intents in allowed do
			local r = resolver(role, if role == "Simulator" then 1 else nil)
			for _, intent in Destinations.INTENTS do
				T.equal(r.allowedHere(intent), intents[intent] == true, `{intent} from {role}`)
				if not intents[intent] then
					local dest, why = r.resolve(intent, profile(1, 1))
					T.equal(dest, nil, `{intent} from {role} resolves to nothing`)
					T.equal(why, `NotFrom{role}`)
				end
			end
		end
		T.isTrue(not resolver("Lobby").isIntent("Teleport"), "unknown intent")
	end)

	test("5.6: the portal leads to the last visited world and zone", function()
		local dest = resolver("Lobby").resolve("Portal", profile(1, 4)) :: any
		T.equal(dest.role, "Simulator")
		T.equal(dest.world, 1)
		T.equal(dest.zone, 4)
		T.equal(dest.placeId, PUBLISHED.Worlds[1])
		T.equal(dest.group, false)

		local second = resolver("Lobby").resolve("Portal", profile(2, 13)) :: any
		T.equal(second.world, 2)
		T.equal(second.zone, 13)
		T.equal(second.placeId, PUBLISHED.Worlds[2])
	end)

	test("an invalid saved world or zone falls back inside a listed world, with a note", function()
		local cases = {
			{ profile = profile(3, 25), world = 1, zone = 1, label = "world not listed" },
			{ profile = profile(1, 15), world = 1, zone = 1, label = "zone of another world" },
			{ profile = profile(2, 0), world = 2, zone = 11, label = "zone 0" },
			{ profile = profile("1", 1.5), world = 1, zone = 1, label = "wrong types" },
			{ profile = {}, world = 1, zone = 1, label = "no sim table" },
		}
		for _, case in cases do
			local dest, why, note = resolver("Lobby").resolve("Portal", case.profile)
			T.equal(why, nil, case.label)
			T.equal((dest :: any).world, case.world, `{case.label}: world`)
			T.equal((dest :: any).zone, case.zone, `{case.label}: zone`)
			T.isTrue(note ~= nil, `{case.label}: noted`)
		end
	end)

	test("5.6: the world gate leads to the first zone of the next world", function()
		local dest = resolver("Simulator", 1).resolve("WorldGate", profile(1, 10)) :: any
		T.equal(dest.role, "Simulator")
		T.equal(dest.world, 2)
		T.equal(dest.zone, ZonesConfig.ZonesPerWorld + 1)
		T.equal(dest.placeId, PUBLISHED.Worlds[2])

		local unpublished = resolver("Simulator", 1, Places).resolve("WorldGate", nil) :: any
		T.equal(unpublished.placeId, 0, "a world without a PlaceId resolves to placeholder 0")

		local last = ZonesConfig.ZoneCount // ZonesConfig.ZonesPerWorld
		local dest2, why = resolver("Simulator", last).resolve("WorldGate", nil)
		T.equal(dest2, nil)
		T.equal(why, "NoNextWorld")
	end)

	test("Lobby, Arena and group destinations", function()
		local sim = resolver("Simulator", 1)
		local lobby = sim.resolve("LobbyButton", nil) :: any
		T.equal(lobby.role, "Lobby")
		T.equal(lobby.placeId, PUBLISHED.Lobby)
		T.equal((sim.resolve("LoadFailReturn", nil) :: any).role, "Lobby")

		local match = resolver("Lobby").resolve("MatchStart", nil) :: any
		T.equal(match.role, "Arena")
		T.equal(match.placeId, PUBLISHED.Arena)
		T.equal(match.group, true)

		local arena = resolver("Arena")
		T.equal((arena.resolve("Replay", nil) :: any).role, "Arena")
		T.equal((arena.resolve("Replay", nil) :: any).group, true)
		T.equal((arena.resolve("ToLobby", nil) :: any).role, "Lobby")
		T.isTrue(arena.isGroup("Replay") and not arena.isGroup("ToLobby"))
	end)
end)

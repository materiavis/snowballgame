--!strict
-- Lobby map binding (ADR 0009 "Lobby (7.1)", ADR 0015) on a fake tree, the box math of the
-- portal volume and the VIP corner, and the web-answer cache (group membership, VIP pass).

local T = require("../../../TestKit")
local FakeClock = require("../../../helpers/FakeClock")
local MapConfig = require("../../../../src/shared/Config/Map")
local AnswerCache = require("../../../../src/places/lobby/server/LobbyMap/AnswerCache")
local Box = require("../../../../src/places/lobby/server/LobbyMap/Box")
local MapRules = require("../../../../src/places/lobby/server/LobbyMap/MapRules")

local function node(fields: { [string]: any }): any
	local out = {
		inMap = true,
		classes = { Model = true },
		primary = {},
		streaming = "Atomic",
		attributes = {},
	}
	for key, value in fields do
		out[key] = value
	end
	return out
end

local rules = MapRules.new({
	stationStreamingMode = MapConfig.StationStreamingMode,
	portalModeAttribute = MapConfig.PortalModeAttribute,
	portalModes = MapConfig.PortalModes,
}, {
	inMap = function(n: any): boolean
		return n.inMap
	end,
	isA = function(n: any, className: string): boolean
		return n.classes[className] == true
	end,
	primaryPart = function(n: any): any
		return n.primary
	end,
	streamingMode = function(n: any): string
		return n.streaming
	end,
	attribute = function(n: any, name: string): any
		return n.attributes[name]
	end,
})

return T.suite("Lobby map contract (ADR 0009) and helpers", function(test)
	test("Config.Map names the Lobby tags and portal attributes of ADR 0009", function()
		for _, tag in { "LobbySpawn", "Portal", "GroupChest", "NewsBoard", "VipCorner" } do
			T.equal(MapConfig.Tags[tag], tag)
		end
		T.equal(MapConfig.PortalModeAttribute, "PortalMode")
		T.equal(MapConfig.PlayerCountAttribute, "PlayerCount")
		T.equal(table.concat(MapConfig.PortalModes, ","), "Singleplayer,Multiplayer")
	end)

	test("portals: a valid station with PortalMode binds; every problem is a warning, never an error", function()
		local good = rules.checkPortal(node({ attributes = { PortalMode = "Singleplayer" } }))
		T.equal(good.status, "Bound")
		T.equal(good.mode, "Singleplayer")
		T.equal(rules.checkPortal(node({ inMap = false })).status, "OutOfScope", "templates outside the map")
		local cases = {
			{ node({ attributes = {} }), "PortalMode is nil" },
			{ node({ attributes = { PortalMode = "Arena" } }), "PortalMode is Arena" },
			{ node({ attributes = { PortalMode = 1 } }), "PortalMode is 1" },
			{ node({ classes = { Part = true }, attributes = { PortalMode = "Multiplayer" } }), "must be a Model" },
			{ node({ primary = false, attributes = { PortalMode = "Multiplayer" } }), "no PrimaryPart" },
			{ node({ streaming = "Default", attributes = { PortalMode = "Multiplayer" } }), "ModelStreamingMode" },
		}
		for _, case in cases do
			local n = case[1]
			if n.primary == false then
				n.primary = nil
			end
			local verdict = rules.checkPortal(n)
			T.equal(verdict.status, "Invalid", case[2])
			T.isTrue(string.find(verdict.problem :: string, case[2], 1, true) ~= nil, `{case[2]}: {verdict.problem}`)
		end
		T.equal(
			MapRules.warning("Portal", "Workspace.Map.X", "Model has no PrimaryPart"),
			"[MapContract] Portal Workspace.Map.X: Model has no PrimaryPart, ignored"
		)
	end)

	test("parts and spawn: class checks", function()
		T.equal(rules.checkPart(node({ classes = { BasePart = true } })).status, "Bound")
		T.equal(rules.checkPart(node({ classes = { Model = true } })).status, "Invalid")
		T.equal(rules.checkSpawn(node({ classes = { SpawnLocation = true, BasePart = true } })).status, "Bound")
		T.equal(rules.checkSpawn(node({ classes = { BasePart = true } })).status, "Invalid")
		T.equal(rules.checkSpawn(node({ inMap = false })).status, "OutOfScope")
	end)

	test("count warnings: none, too many, fine", function()
		T.isTrue(MapRules.countWarning("LobbySpawn", 0, "one") ~= nil)
		T.isTrue(MapRules.countWarning("LobbySpawn", 2, "one") ~= nil)
		T.equal(MapRules.countWarning("LobbySpawn", 1, "one"), nil)
		T.equal(MapRules.countWarning("VipCorner", 3, "some"), nil)
		T.isTrue(MapRules.countWarning("VipCorner", 0, "some") ~= nil)
	end)

	test("box: inside includes the surface; push-out goes through the nearest side wall", function()
		local size = { 10, 10, 4 }
		T.isTrue(Box.contains(0, 0, 0, size))
		T.isTrue(Box.contains(5, 5, 2, size), "on the surface")
		T.equal(Box.contains(5.01, 0, 0, size), false)
		T.equal(Box.contains(0, 0, -2.01, size), false)
		-- Nearest wall is z (2 away) for the centre of a 10 x 4 footprint.
		local x, y, z = Box.pushOut(0, 1, 0.5, size, 3)
		T.equal(x, 0)
		T.equal(y, 1, "height kept")
		T.equal(z, 5, "out through +z, 3 studs past the wall")
		x, _, z = Box.pushOut(-4.5, 0, 0, size, 3)
		T.equal(x, -8, "out through -x")
		T.equal(z, 0)
		T.equal(Box.contains(x, 0, z, size), false, "the result is outside")
		x, y, z = Box.pushOut(20, 0, 0, size, 3)
		T.equal(x, 20, "outside stays where it is")
	end)

	test("answer cache: yes kept, no asked again after the recheck time, failures never kept", function()
		local clock = FakeClock.new(0)
		local answers: { any } = { false, true }
		local asked = 0
		local cache = AnswerCache.new(function()
			asked += 1
			return table.remove(answers, 1)
		end, 10, clock.now)
		T.equal(cache.get(1), false)
		T.equal(cache.get(1), false, "cached no")
		T.equal(asked, 1)
		clock.advance(10)
		T.equal(cache.get(1), true, "asked again after 10 s")
		clock.advance(1000)
		T.equal(cache.get(1), true, "yes is kept")
		T.equal(asked, 2)
		answers = { nil :: any, true }
		cache.forget(1)
		T.equal(cache.get(1), nil, "failed call")
		T.equal(cache.get(1), true, "a failure is not cached")
		T.equal(asked, 4)
	end)
end)

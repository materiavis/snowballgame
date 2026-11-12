--!strict
-- Upgrade stand binding rules (#36, ADR 0009): zone resolve from the area root's ZoneIndex,
-- the Workspace.Map scope, the Station rule and the warning text, on a fake Instance tree.
-- World 1 has no zone area yet (#29), so this is the stand's evidence until then.

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local MapConfig = require("../../../../src/shared/Config/Map")
local StationRules = require("../../../../src/places/simulator/server/UpgradeService/StationRules")

type Node = {
	name: string,
	parent: Node?,
	children: { Node },
	model: boolean,
	primary: boolean,
	streaming: string,
	zone: any,
}

local function node(name: string, parent: Node?, fields: { [string]: any }?): Node
	local n: Node = {
		name = name,
		parent = parent,
		children = {},
		model = false,
		primary = false,
		streaming = "Default",
		zone = nil,
	}
	for key, value in fields or {} do
		(n :: any)[key] = value
	end
	if parent then
		table.insert(parent.children, n)
	end
	return n
end

local function stand(name: string, parent: Node, fields: { [string]: any }?): Node
	local base = { model = true, primary = true, streaming = "Atomic" }
	for key, value in fields or {} do
		base[key] = value
	end
	return node(name, parent, base)
end

type Scene = { workspace: Node, map: Node, rules: StationRules.Rules }

local function scene(worldIndex: number?): Scene
	local workspace = node("Workspace", nil)
	local map = node("Map", workspace)
	local rules = StationRules.new({
		worldIndex = worldIndex or 1,
		zoneCount = E.Config.Zones.ZoneCount,
		isZone = E.Zones.isZone,
		worldOf = E.Zones.worldOf,
		stationStreamingMode = MapConfig.StationStreamingMode,
		zoneIndexAttribute = MapConfig.ZoneIndexAttribute,
	}, {
		parent = function(n: any): any
			return n.parent
		end,
		isMapRoot = function(n: any): boolean
			return n == map
		end,
		mapChildren = function(): { any }
			return map.children
		end,
		isModel = function(n: any): boolean
			return n.model
		end,
		primaryPart = function(n: any): any
			return if n.primary then {} else nil
		end,
		streamingMode = function(n: any): string
			return n.streaming
		end,
		zoneIndex = function(n: any): any
			return n.zone
		end,
		name = function(n: any): string
			return n.name
		end,
	})
	return { workspace = workspace, map = map, rules = rules }
end

return T.suite("UpgradeService.StationRules (ADR 0009)", function(test)
	test("a stand deep inside a zone area binds with the area's ZoneIndex", function()
		local s = scene()
		local zone3 = node("Zone03", s.map, { zone = 3 })
		local decor = node("End", zone3)
		local model = stand("UpgradeStand", decor)
		local verdict = s.rules.checkStation(model)
		T.equal(verdict.status, "Bound")
		T.equal(verdict.zone, 3)
		T.equal(s.rules.areaOf(model), zone3)
		T.equal(s.rules.zoneOf(model), 3)
	end)

	test("outside Workspace.Map (a template) is ignored without a warning", function()
		local s = scene()
		local kit = node("Kit", nil)
		local verdict = s.rules.checkStation(stand("UpgradeStand", kit))
		T.equal(verdict.status, "OutOfScope")
		T.equal(verdict.problem, nil)
		local inWorkspace = stand("Loose", s.workspace)
		T.equal(s.rules.checkStation(inWorkspace).status, "OutOfScope")
	end)

	test("an area without ZoneIndex (today's Placeholder) gives no zone: warn and ignore", function()
		local s = scene()
		local placeholder = node("Placeholder", s.map)
		local verdict = s.rules.checkStation(stand("UpgradeStand", placeholder))
		T.equal(verdict.status, "Invalid")
		T.isTrue(
			string.find(verdict.problem :: string, "Placeholder has no ZoneIndex", 1, true) ~= nil,
			verdict.problem
		)
	end)

	test("an invalid ZoneIndex warns: not whole, out of range, wrong type or another world", function()
		for _, bad in { 0, 1.5, 51, -2, "3", 0 / 0, 11 } do
			local s = scene()
			local area = node("Zone", s.map, { zone = bad })
			local verdict = s.rules.checkStation(stand("UpgradeStand", area))
			T.equal(verdict.status, "Invalid", `ZoneIndex {tostring(bad)}`)
			T.isTrue(string.find(verdict.problem :: string, "invalid ZoneIndex", 1, true) ~= nil, verdict.problem)
		end
		-- Zone 11 is valid in world 2.
		local s2 = scene(2)
		local area = node("Zone11", s2.map, { zone = 11 })
		T.equal(s2.rules.checkStation(stand("UpgradeStand", area)).status, "Bound")
	end)

	test("two areas with the same ZoneIndex both have no zone", function()
		local s = scene()
		local a = node("Zone02", s.map, { zone = 2 })
		local b = node("Zone02Copy", s.map, { zone = 2 })
		for _, area in { a, b } do
			local verdict = s.rules.checkStation(stand("UpgradeStand", area))
			T.equal(verdict.status, "Invalid")
			T.isTrue(string.find(verdict.problem :: string, "shares ZoneIndex 2", 1, true) ~= nil, verdict.problem)
		end
	end)

	test("Station rule: Model, PrimaryPart and Atomic streaming", function()
		local s = scene()
		local area = node("Zone01", s.map, { zone = 1 })
		local part = node("TaggedPart", area)
		T.isTrue(
			string.find(s.rules.checkStation(part).problem :: string, "must be a Model", 1, true) ~= nil,
			"tag on a part"
		)
		local noPrimary = stand("NoPrimary", area, { primary = false })
		T.equal(s.rules.checkStation(noPrimary).problem, "Model has no PrimaryPart")
		local streaming = stand("Streaming", area, { streaming = "Default" })
		T.equal(s.rules.checkStation(streaming).problem, "ModelStreamingMode is Default, expected Atomic")
		T.equal(s.rules.checkStation(stand("Good", area)).status, "Bound")
	end)

	test("a stand that is itself a direct child of Workspace.Map is its own area and needs a ZoneIndex", function()
		local s = scene()
		local direct = stand("UpgradeStand", s.map)
		T.equal(s.rules.checkStation(direct).status, "Invalid")
		direct.zone = 4
		T.equal(s.rules.checkStation(direct).zone, 4)
	end)

	test("the warning has the ADR 0009 shape", function()
		T.equal(
			StationRules.warning("UpgradeStand", "Workspace.Map.Placeholder.UpgradeStand", "Model has no PrimaryPart"),
			"[MapContract] UpgradeStand Workspace.Map.Placeholder.UpgradeStand: Model has no PrimaryPart, ignored"
		)
	end)

	test("Config.Map names follow ADR 0009", function()
		T.equal(MapConfig.FolderName, "Map")
		T.equal(MapConfig.ZoneIndexAttribute, "ZoneIndex")
		T.equal(MapConfig.Tags.UpgradeStand, "UpgradeStand")
		T.equal(MapConfig.StationStreamingMode, "Atomic")
		T.equal(MapConfig.LabelAnchorName, "LabelAnchor")
	end)
end)

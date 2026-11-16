--!strict
-- Map contract checks for a zone-bound station (ADR 0009 "General rules", "Zone number" and the
-- Station rule). Pure: the Instance tree is reached through the injected `Tree`, so a headless
-- spec checks the rules on a fake tree. Used by the upgrade stand (#36); written without
-- upgrade words so #38-#41 can lift it into a shared resolver.

export type Tree = {
	parent: (node: any) -> any,
	-- True only for Workspace.Map itself.
	isMapRoot: (node: any) -> boolean,
	-- Direct children of Workspace.Map (the zone area roots).
	mapChildren: () -> { any },
	isModel: (node: any) -> boolean,
	primaryPart: (node: any) -> any,
	-- Enum.ModelStreamingMode name of a Model.
	streamingMode: (node: any) -> string,
	-- The area's ZoneIndex attribute value, whatever its type.
	zoneIndex: (node: any) -> any,
	name: (node: any) -> string,
}

export type Options = {
	worldIndex: number,
	zoneCount: number,
	isZone: (value: any) -> boolean,
	worldOf: (zone: number) -> number,
	stationStreamingMode: string,
	zoneIndexAttribute: string,
}

-- Bound: use it (zone set). OutOfScope: not under Workspace.Map, ignore without a warning
-- (templates). Invalid: warn once with `problem` and ignore.
export type Verdict = {
	status: "Bound" | "OutOfScope" | "Invalid",
	zone: number?,
	problem: string?,
}

export type Rules = {
	areaOf: (node: any) -> any,
	zoneOf: (node: any) -> (number?, string?),
	checkStation: (node: any) -> Verdict,
}

local StationRules = {}

-- `[MapContract] <tag> <full name>: <problem>, ignored` (ADR 0009).
function StationRules.warning(tag: string, fullName: string, problem: string): string
	return `[MapContract] {tag} {fullName}: {problem}, ignored`
end

function StationRules.new(options: Options, tree: Tree): Rules
	-- The direct child of Workspace.Map that holds `node` (or is it), or nil outside the map.
	local function areaOf(node: any): any
		local current = node
		while current ~= nil do
			local parent = tree.parent(current)
			if parent == nil then
				return nil
			end
			if tree.isMapRoot(parent) then
				return current
			end
			current = parent
		end
		return nil
	end

	local function validZone(value: any): boolean
		return options.isZone(value) and options.worldOf(value) == options.worldIndex
	end

	-- The zone of an area root, or nil and the problem.
	local function zoneOfArea(area: any): (number?, string?)
		local value = tree.zoneIndex(area)
		local attribute = options.zoneIndexAttribute
		if value == nil then
			return nil, `zone area {tree.name(area)} has no {attribute}`
		end
		if not validZone(value) then
			return nil,
				`zone area {tree.name(area)} has invalid {attribute} {tostring(value)} (whole number 1..{options.zoneCount} in world {options.worldIndex})`
		end
		for _, other in tree.mapChildren() do
			if other ~= area and tree.zoneIndex(other) == value then
				return nil, `zone area {tree.name(area)} shares {attribute} {value} with {tree.name(other)}`
			end
		end
		return value, nil
	end

	-- nil, nil outside Workspace.Map; nil, problem without a valid zone.
	local function zoneOf(node: any): (number?, string?)
		local area = areaOf(node)
		if area == nil then
			return nil, nil
		end
		return zoneOfArea(area)
	end

	local function checkStation(node: any): Verdict
		local area = areaOf(node)
		if area == nil then
			return { status = "OutOfScope" }
		end
		local zone, problem = zoneOfArea(area)
		if zone == nil then
			return { status = "Invalid", problem = `not in a zone: {problem}` }
		end
		if not tree.isModel(node) then
			return { status = "Invalid", problem = "a station must be a Model with the tag on the Model" }
		end
		if tree.primaryPart(node) == nil then
			return { status = "Invalid", problem = "Model has no PrimaryPart" }
		end
		local mode = tree.streamingMode(node)
		if mode ~= options.stationStreamingMode then
			return {
				status = "Invalid",
				problem = `ModelStreamingMode is {mode}, expected {options.stationStreamingMode}`,
			}
		end
		return { status = "Bound", zone = zone }
	end

	return table.freeze({
		areaOf = areaOf,
		zoneOf = zoneOf,
		checkStation = checkStation,
	})
end

return table.freeze(StationRules)

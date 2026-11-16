--!strict
-- Map contract checks for the Lobby entries (ADR 0009 "General rules" and "Lobby (7.1)").
-- Pure: the Instance tree is reached through the injected `Tree`, so a headless spec checks the
-- rules on a fake tree. The Lobby has no zones, so this is the zone-free sibling of the
-- Simulator's StationRules.

export type Tree = {
	-- True when the node is a descendant of Workspace.Map.
	inMap: (node: any) -> boolean,
	isA: (node: any, className: string) -> boolean,
	primaryPart: (node: any) -> any,
	-- Enum.ModelStreamingMode name of a Model.
	streamingMode: (node: any) -> string,
	attribute: (node: any, name: string) -> any,
}

export type Options = {
	stationStreamingMode: string,
	portalModeAttribute: string,
	portalModes: { string },
}

-- Bound: use it. OutOfScope: not under Workspace.Map, ignore without a warning (templates).
-- Invalid: warn once with `problem` and ignore.
export type Verdict = {
	status: "Bound" | "OutOfScope" | "Invalid",
	problem: string?,
	mode: string?, -- portals only
}

export type Rules = {
	checkStation: (node: any) -> Verdict,
	checkPortal: (node: any) -> Verdict,
	checkPart: (node: any) -> Verdict,
	checkSpawn: (node: any) -> Verdict,
}

local MapRules = {}

-- `[MapContract] <tag> <full name>: <problem>, ignored` (ADR 0009).
function MapRules.warning(tag: string, fullName: string, problem: string): string
	return `[MapContract] {tag} {fullName}: {problem}, ignored`
end

-- The warning for a tag whose count is wrong, or nil when the count is fine.
-- `expected` is "one" (exactly 1) or "some" (at least 1).
function MapRules.countWarning(tag: string, count: number, expected: "one" | "some"): string?
	if count == 0 then
		return `[MapContract] {tag}: none in Workspace.Map`
	end
	if expected == "one" and count > 1 then
		return `[MapContract] {tag}: {count} in Workspace.Map, expected 1`
	end
	return nil
end

function MapRules.new(options: Options, tree: Tree): Rules
	local function invalid(problem: string): Verdict
		return { status = "Invalid", problem = problem }
	end

	local function checkStation(node: any): Verdict
		if not tree.inMap(node) then
			return { status = "OutOfScope" }
		end
		if not tree.isA(node, "Model") then
			return invalid("a station must be a Model with the tag on the Model")
		end
		if tree.primaryPart(node) == nil then
			return invalid("Model has no PrimaryPart")
		end
		local mode = tree.streamingMode(node)
		if mode ~= options.stationStreamingMode then
			return invalid(`ModelStreamingMode is {mode}, expected {options.stationStreamingMode}`)
		end
		return { status = "Bound" }
	end

	local function checkPortal(node: any): Verdict
		local verdict = checkStation(node)
		if verdict.status ~= "Bound" then
			return verdict
		end
		local attribute = options.portalModeAttribute
		local mode = tree.attribute(node, attribute)
		if type(mode) ~= "string" or table.find(options.portalModes, mode) == nil then
			local allowed = table.concat(options.portalModes, " or ")
			return invalid(`{attribute} is {tostring(mode)}, expected {allowed}`)
		end
		return { status = "Bound", mode = mode }
	end

	local function checkPart(node: any): Verdict
		if not tree.inMap(node) then
			return { status = "OutOfScope" }
		end
		if not tree.isA(node, "BasePart") then
			return invalid("expected a BasePart")
		end
		return { status = "Bound" }
	end

	local function checkSpawn(node: any): Verdict
		if not tree.inMap(node) then
			return { status = "OutOfScope" }
		end
		if not tree.isA(node, "SpawnLocation") then
			return invalid("expected a SpawnLocation")
		end
		return { status = "Bound" }
	end

	return table.freeze({
		checkStation = checkStation,
		checkPortal = checkPortal,
		checkPart = checkPart,
		checkSpawn = checkSpawn,
	})
end

return table.freeze(MapRules)

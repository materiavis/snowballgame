--!strict
-- Zone contract check: the ADR 0009 rules for one zone area root (`world/<world>/ZoneNN.rbxmx`),
-- plus optional counts from Config.Map.ZoneContract. Pure: it gets an Instance tree from
-- @lune/roblox and returns a list of problems, so the spec can feed it built fixtures and real
-- files alike. Every problem names the instance's path, so a builder can find it.

local Ball = require("../../src/shared/Config/Ball")
local Map = require("../../src/shared/Config/Map")

export type Range = { Min: number?, Max: number? }
export type Rules = {
	Counts: { [string]: Range },
	KnockOverShare: Range?,
}

local ZoneContract = {}

local Tags = Map.Tags
-- ADR 0009 names WorldGate, but no code binds it yet, so it is not in Config.Map.Tags.
local WORLD_GATE_TAG = "WorldGate"
local STATION_TAGS = { Tags.UpgradeStand, Tags.EggStation, Tags.Barrier, WORLD_GATE_TAG }
-- Tags whose instance must be an anchor (Attachment or BasePart).
local ANCHOR_TAGS = { Tags.ZoneStart, Tags.FindPoint, Ball.ScaleAnchorTag }
-- Tags whose instance must be a BasePart.
local PART_TAGS = { Tags.ScalePlate, Ball.ObstacleTag }
for _, surface in Ball.Surfaces do
	table.insert(PART_TAGS, surface)
end

local function pathOf(instance: any, root: any): string
	local names = {}
	local current = instance
	while current and current ~= root.Parent do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end
	return table.concat(names, ".")
end

local function isAnchor(instance: any): boolean
	return instance:IsA("Attachment") or instance:IsA("BasePart")
end

local function isWhole(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0
end

local function isPositiveFinite(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- The object a tagged instance belongs to when counting: its nearest Model ancestor (an object
-- made of several parts counts once), else the instance itself.
local function objectOf(instance: any, root: any): any
	local current = instance
	while current and current ~= root do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return instance
end

-- The rules for one world folder: the global counts, overridden per world.
function ZoneContract.rulesFor(worldName: string): Rules
	local contract = Map.ZoneContract
	local world = contract.Worlds[worldName]
	return {
		Counts = (world and world.Counts) or contract.Counts,
		KnockOverShare = if world and world.KnockOverShare then world.KnockOverShare else contract.KnockOverShare,
	}
end

-- The zone number in a file name, or nil when the file is not a zone area file.
function ZoneContract.fileZone(fileName: string): number?
	local digits = string.match(fileName, Map.ZoneContract.FilePattern)
	return if digits then tonumber(digits) else nil
end

local function checkRange(problems: { string }, label: string, value: number, range: Range)
	if range.Min and value < range.Min then
		table.insert(problems, `{label}: {value}, needs at least {range.Min}`)
	end
	if range.Max and value > range.Max then
		table.insert(problems, `{label}: {value}, allows at most {range.Max}`)
	end
end

-- All problems of one zone area root. `fileZone` is the number from the file name, nil to skip
-- the name check (fixtures).
function ZoneContract.check(root: any, fileZone: number?, rules: Rules): { string }
	local problems: { string } = {}
	local function problem(instance: any, text: string)
		table.insert(problems, `{pathOf(instance, root)}: {text}`)
	end

	-- Root: Folder or a non-atomic, non-persistent Model, with a whole ZoneIndex.
	if root:IsA("Model") then
		local mode = root.ModelStreamingMode.Name
		if mode == "Atomic" or mode == "Persistent" then
			problem(root, `zone area root must not use ModelStreamingMode {mode}`)
		end
	elseif not root:IsA("Folder") then
		problem(root, `zone area root must be a Folder or Model, is {root.ClassName}`)
	end
	local zoneIndex = root:GetAttribute(Map.ZoneIndexAttribute)
	if not (isWhole(zoneIndex) and zoneIndex >= 1 and zoneIndex <= Map.ZoneContract.MaxZoneIndex) then
		problem(
			root,
			`{Map.ZoneIndexAttribute} must be a whole number 1-{Map.ZoneContract.MaxZoneIndex}, is {zoneIndex}`
		)
	elseif fileZone and zoneIndex ~= fileZone then
		problem(
			root,
			`{Map.ZoneIndexAttribute} {zoneIndex} does not match the file name (Zone{string.format("%02d", fileZone)})`
		)
	end

	local tagged: { [string]: { any } } = {}
	for _, instance in root:GetDescendants() do
		if instance:GetAttribute(Map.ZoneIndexAttribute) ~= nil then
			problem(instance, `{Map.ZoneIndexAttribute} only belongs on the zone area root`)
		end
		for _, tag in instance:GetTags() do
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], instance)
		end
	end

	-- Exactly one ZoneStart.
	local starts = tagged[Tags.ZoneStart] or {}
	if #starts ~= 1 then
		problem(root, `needs exactly 1 {Tags.ZoneStart}, has {#starts}`)
	end

	for _, tag in ANCHOR_TAGS do
		for _, instance in tagged[tag] or {} do
			if not isAnchor(instance) then
				problem(instance, `{tag} must be an Attachment or BasePart, is {instance.ClassName}`)
			end
		end
	end
	for _, tag in PART_TAGS do
		for _, instance in tagged[tag] or {} do
			if not instance:IsA("BasePart") then
				problem(instance, `{tag} must be a BasePart, is {instance.ClassName}`)
			end
		end
	end

	-- Stations: Model, PrimaryPart inside it, Atomic streaming.
	for _, tag in STATION_TAGS do
		for _, instance in tagged[tag] or {} do
			if not instance:IsA("Model") then
				problem(instance, `{tag} must be a Model, is {instance.ClassName}`)
				continue
			end
			local primary = instance.PrimaryPart
			if not primary or not primary:IsDescendantOf(instance) then
				problem(instance, `{tag} needs a PrimaryPart inside the Model`)
			end
			if instance.ModelStreamingMode.Name ~= Map.StationStreamingMode then
				problem(instance, `{tag} needs ModelStreamingMode {Map.StationStreamingMode}`)
			end
		end
	end

	-- KnockOverSize, when set, must be a positive finite number.
	for _, instance in tagged[Ball.ObstacleTag] or {} do
		local size = instance:GetAttribute(Ball.KnockOverSizeAttribute)
		if size ~= nil and not isPositiveFinite(size) then
			problem(instance, `{Ball.KnockOverSizeAttribute} must be a positive number, is {size}`)
		end
	end

	-- Invisible walls at the zone edge: a Bounds folder of anchored, colliding, invisible parts.
	local boundsName = Map.ZoneContract.BoundsFolderName
	local bounds = root:FindFirstChild(boundsName)
	if not bounds then
		problem(root, `needs a {boundsName} folder with the invisible walls`)
	else
		local walls = 0
		for _, wall in bounds:GetDescendants() do
			if wall:IsA("BasePart") then
				walls += 1
				if wall.Transparency ~= 1 or not wall.CanCollide or not wall.Anchored then
					problem(wall, "wall must be Transparency 1, CanCollide and Anchored")
				end
			end
		end
		if walls == 0 then
			problem(bounds, "has no wall parts")
		end
	end

	-- Optional counts per tag, counted per object (see objectOf).
	for tag, range in rules.Counts do
		local objects: { [any]: boolean } = {}
		local count = 0
		for _, instance in tagged[tag] or {} do
			local object = objectOf(instance, root)
			if not objects[object] then
				objects[object] = true
				count += 1
			end
		end
		checkRange(problems, `{root.Name}: {tag} objects`, count, range)
	end

	if rules.KnockOverShare then
		local objects: { [any]: boolean } = {}
		local total, knockable = 0, 0
		for _, instance in tagged[Ball.ObstacleTag] or {} do
			local object = objectOf(instance, root)
			local canKnock = isPositiveFinite(instance:GetAttribute(Ball.KnockOverSizeAttribute))
			if objects[object] == nil then
				objects[object] = canKnock
				total += 1
				if canKnock then
					knockable += 1
				end
			elseif canKnock and not objects[object] then
				objects[object] = true
				knockable += 1
			end
		end
		if total > 0 then
			checkRange(problems, `{root.Name}: knock-over share`, knockable / total, rules.KnockOverShare)
		end
	end

	table.sort(problems)
	return problems
end

-- Problems across all zone areas of one world: a ZoneIndex used twice.
function ZoneContract.checkWorld(roots: { any }): { string }
	local problems: { string } = {}
	local seen: { [number]: string } = {}
	for _, root in roots do
		local zoneIndex = root:GetAttribute(Map.ZoneIndexAttribute)
		if isWhole(zoneIndex) then
			if seen[zoneIndex] then
				table.insert(problems, `{Map.ZoneIndexAttribute} {zoneIndex} used by {seen[zoneIndex]} and {root.Name}`)
			else
				seen[zoneIndex] = root.Name
			end
		end
	end
	return problems
end

return table.freeze(ZoneContract)

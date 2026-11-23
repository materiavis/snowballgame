--!strict
-- Zone contract check (concept 6.2, ADR 0009, #29): every World 1 zone area in world/world1 has
-- 15-25 obstacles, 40-60 % of them knock-over-able, 2-3 deep-snow fields and 8-12 find points
-- (limits in Config.Map.LevelDesign). An obstacle is a kit Model holding Obstacle parts and a
-- field is a Folder holding DeepSnow parts, so one tree with three collision parts counts once.
-- Map files without a ZoneIndex root (e.g. Placeholder) are not zones and are skipped.

local fs = require("@lune/fs")
local Roblox = require("@lune/roblox")
local T = require("../TestKit")
local Ball = require("../../src/shared/Config/Ball")
local Map = require("../../src/shared/Config/Map")

local WORLD_DIR = "world/world1"
local LIMITS = Map.LevelDesign

type Counts = {
	obstacles: number,
	knockOver: number,
	deepSnowFields: number,
	findPoints: number,
	problems: { string },
}

-- The nearest ancestor of `instance` of class `className` strictly below the zone root.
local function ownerBelow(instance: any, root: any, className: string): any?
	local current = instance.Parent
	while current and current ~= root do
		if current.ClassName == className then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isKnockOver(part: any): boolean
	local size = part:GetAttribute(Ball.KnockOverSizeAttribute)
	return type(size) == "number" and size == size and size > 0 and size < math.huge
end

local function countZone(root: any): Counts
	local problems: { string } = {}
	-- Model -> { all = number of Obstacle parts, knockOver = how many carry KnockOverSize }
	local obstacleModels: { [any]: { all: number, knockOver: number } } = {}
	local fields: { [any]: boolean } = {}
	local findPoints = 0

	for _, instance in root:GetDescendants() do
		if instance:HasTag(Ball.ObstacleTag) and instance:IsA("BasePart") then
			local model = ownerBelow(instance, root, "Model")
			if model then
				local entry = obstacleModels[model] or { all = 0, knockOver = 0 }
				entry.all += 1
				if isKnockOver(instance) then
					entry.knockOver += 1
				end
				obstacleModels[model] = entry
			else
				table.insert(problems, `Obstacle part {instance:GetFullName()} is not inside a kit Model`)
			end
		end
		if instance:HasTag(Ball.Surfaces.DeepSnow) and instance:IsA("BasePart") then
			local folder = ownerBelow(instance, root, "Folder")
			if folder then
				fields[folder] = true
			else
				table.insert(problems, `DeepSnow part {instance:GetFullName()} is not inside a field Folder`)
			end
		end
		if instance:HasTag(Map.Tags.FindPoint) then
			findPoints += 1
		end
	end

	local obstacles, knockOver = 0, 0
	for model, entry in obstacleModels do
		obstacles += 1
		if entry.knockOver == entry.all then
			knockOver += 1
		elseif entry.knockOver > 0 then
			table.insert(
				problems,
				`Model {model:GetFullName()}: only {entry.knockOver} of {entry.all} Obstacle parts carry KnockOverSize`
			)
		end
	end
	local deepSnowFields = 0
	for _ in fields do
		deepSnowFields += 1
	end

	return {
		obstacles = obstacles,
		knockOver = knockOver,
		deepSnowFields = deepSnowFields,
		findPoints = findPoints,
		problems = problems,
	}
end

local function inRange(value: number, range: { Min: number, Max: number }): boolean
	return value >= range.Min and value <= range.Max
end

-- Every contract violation of one zone, empty when the zone passes.
local function violations(counts: Counts): { string }
	local out = table.clone(counts.problems)
	if not inRange(counts.obstacles, LIMITS.Obstacles) then
		table.insert(out, `{counts.obstacles} obstacles, expected {LIMITS.Obstacles.Min}-{LIMITS.Obstacles.Max}`)
	end
	local share = if counts.obstacles > 0 then counts.knockOver / counts.obstacles else 0
	if not inRange(share, LIMITS.KnockOverShare) then
		table.insert(
			out,
			`{counts.knockOver} of {counts.obstacles} obstacles knock-over-able ({math.floor(share * 100 + 0.5)} %), expected {LIMITS.KnockOverShare.Min * 100}-{LIMITS.KnockOverShare.Max * 100} %`
		)
	end
	if not inRange(counts.deepSnowFields, LIMITS.DeepSnowFields) then
		table.insert(
			out,
			`{counts.deepSnowFields} deep-snow fields, expected {LIMITS.DeepSnowFields.Min}-{LIMITS.DeepSnowFields.Max}`
		)
	end
	if not inRange(counts.findPoints, LIMITS.FindPoints) then
		table.insert(out, `{counts.findPoints} find points, expected {LIMITS.FindPoints.Min}-{LIMITS.FindPoints.Max}`)
	end
	return out
end

-- Test fixture: a zone area built in memory with the given content.
local function fakeZone(spec: { big: number, small: number, fields: number, finds: number, partsPerObstacle: number? })
	local root = Roblox.Instance.new("Folder")
	root.Name = "ZoneTest"
	root:SetAttribute(Map.ZoneIndexAttribute, 1)
	local parts = spec.partsPerObstacle or 1
	local function obstacle(name: string, knockOver: boolean)
		local model = Roblox.Instance.new("Model")
		model.Name = name
		model.Parent = root
		for i = 1, parts do
			local part = Roblox.Instance.new("Part")
			part.Name = `Collision{i}`
			part:AddTag(Ball.ObstacleTag)
			if knockOver then
				part:SetAttribute(Ball.KnockOverSizeAttribute, 4)
			end
			part.Parent = model
		end
	end
	for i = 1, spec.big do
		obstacle(`Big{i}`, false)
	end
	for i = 1, spec.small do
		obstacle(`Small{i}`, true)
	end
	for i = 1, spec.fields do
		local folder = Roblox.Instance.new("Folder")
		folder.Name = `DeepSnow{i}`
		folder.Parent = root
		for j = 1, 3 do
			local part = Roblox.Instance.new("Part")
			part.Name = `Patch{j}`
			part:AddTag(Ball.Surfaces.DeepSnow)
			part.Parent = folder
		end
	end
	for i = 1, spec.finds do
		local anchor = Roblox.Instance.new("Attachment")
		anchor.Name = `Find{i}`
		anchor:AddTag(Map.Tags.FindPoint)
		anchor.Parent = root
	end
	return root
end

local function zoneFiles(): { string }
	local out: { string } = {}
	for _, entry in fs.readDir(WORLD_DIR) do
		if string.sub(entry, -#".rbxmx") == ".rbxmx" or string.sub(entry, -#".rbxm") == ".rbxm" then
			table.insert(out, `{WORLD_DIR}/{entry}`)
		end
	end
	table.sort(out)
	return out
end

return T.suite("world/ZoneContract", function(test)
	test("limits are the concept 6.2 numbers", function()
		T.equal(LIMITS.Obstacles.Min, 15)
		T.equal(LIMITS.Obstacles.Max, 25)
		T.equal(LIMITS.KnockOverShare.Min, 0.4)
		T.equal(LIMITS.KnockOverShare.Max, 0.6)
		T.equal(LIMITS.DeepSnowFields.Min, 2)
		T.equal(LIMITS.DeepSnowFields.Max, 3)
		T.equal(LIMITS.FindPoints.Min, 8)
		T.equal(LIMITS.FindPoints.Max, 12)
	end)

	test("counter: a valid zone passes, one Model with several parts counts once", function()
		local counts = countZone(fakeZone({ big = 10, small = 10, fields = 2, finds = 10, partsPerObstacle = 3 }))
		T.equal(counts.obstacles, 20, "obstacle Models")
		T.equal(counts.knockOver, 10, "knock-over Models")
		T.equal(counts.deepSnowFields, 2, "fields, not parts")
		T.equal(counts.findPoints, 10)
		T.equal(#violations(counts), 0, table.concat(violations(counts), "; "))
	end)

	test("counter: limits are inclusive", function()
		-- 15 obstacles with 6 small = 40 %, 25 with 15 small = 60 %
		T.equal(#violations(countZone(fakeZone({ big = 9, small = 6, fields = 2, finds = 8 }))), 0, "lower")
		T.equal(#violations(countZone(fakeZone({ big = 10, small = 15, fields = 3, finds = 12 }))), 0, "upper")
	end)

	test("counter: each limit fails just outside its range", function()
		local cases = {
			{ name = "14 obstacles", zone = { big = 7, small = 7, fields = 2, finds = 10 }, pattern = "14 obstacles" },
			{
				name = "26 obstacles",
				zone = { big = 13, small = 13, fields = 2, finds = 10 },
				pattern = "26 obstacles",
			},
			{ name = "share 35 %", zone = { big = 13, small = 7, fields = 2, finds = 10 }, pattern = "35 %" },
			{ name = "share 65 %", zone = { big = 7, small = 13, fields = 2, finds = 10 }, pattern = "65 %" },
			{ name = "1 field", zone = { big = 10, small = 10, fields = 1, finds = 10 }, pattern = "1 deep-snow" },
			{ name = "4 fields", zone = { big = 10, small = 10, fields = 4, finds = 10 }, pattern = "4 deep-snow" },
			{ name = "7 finds", zone = { big = 10, small = 10, fields = 2, finds = 7 }, pattern = "7 find" },
			{ name = "13 finds", zone = { big = 10, small = 10, fields = 2, finds = 13 }, pattern = "13 find" },
		}
		for _, case in cases do
			local found = violations(countZone(fakeZone(case.zone)))
			T.equal(#found, 1, case.name)
			T.isTrue(string.find(found[1], case.pattern, 1, true) ~= nil, `{case.name}: {found[1]}`)
		end
	end)

	test("counter: loose Obstacle and DeepSnow parts and mixed Models are reported", function()
		local root = fakeZone({ big = 10, small = 10, fields = 2, finds = 10, partsPerObstacle = 2 })
		local loose = Roblox.Instance.new("Part")
		loose.Name = "LooseRock"
		loose:AddTag(Ball.ObstacleTag)
		loose.Parent = root
		local patch = Roblox.Instance.new("Part")
		patch.Name = "LoosePatch"
		patch:AddTag(Ball.Surfaces.DeepSnow)
		patch.Parent = root
		local small1 = root:FindFirstChild("Small1") :: any
		small1:FindFirstChild("Collision1"):SetAttribute(Ball.KnockOverSizeAttribute, nil)
		local found = table.concat(violations(countZone(root)), "\n")
		T.isTrue(string.find(found, "LooseRock is not inside a kit Model") ~= nil, found)
		T.isTrue(string.find(found, "LoosePatch is not inside a field Folder") ~= nil, found)
		T.isTrue(string.find(found, "only 1 of 2 Obstacle parts") ~= nil, found)
	end)

	test("every zone area in world/world1 meets the contract", function()
		local report: { string } = {}
		local checked = 0
		for _, path in zoneFiles() do
			local roots = Roblox.deserializeModel(fs.readFile(path))
			for _, root in roots do
				if type(root:GetAttribute(Map.ZoneIndexAttribute)) ~= "number" then
					continue -- not a zone area (ADR 0009), e.g. Placeholder
				end
				checked += 1
				for _, problem in violations(countZone(root)) do
					table.insert(report, `{path} ({root.Name}): {problem}`)
				end
			end
		end
		print(`    ZoneContract: {checked} zone area(s) checked in {WORLD_DIR}`)
		T.equal(#report, 0, "\n" .. table.concat(report, "\n"))
	end)
end)

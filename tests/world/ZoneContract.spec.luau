--!strict
-- Zone contract check (ADR 0009). Part 1 proves the checker on built fixtures, so a green run on
-- real files means something. Part 2 checks every world/<world>/ZoneNN.rbxmx in the repository.
-- Counts come from Config.Map.ZoneContract; the fixture numbers here are test values.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local T = require("../TestKit")
local ZoneContract = require("../helpers/ZoneContract")
local Map = require("../../src/shared/Config/Map")
local Ball = require("../../src/shared/Config/Ball")

local Instance = roblox.Instance
local Enum = roblox.Enum

local NO_COUNTS: ZoneContract.Rules = { Counts = {} }

-- Any surface tag from Config; the checker treats them all alike.
local surfaceNames = {}
for _, name in Ball.Surfaces do
	table.insert(surfaceNames, name)
end
table.sort(surfaceNames)
local SURFACE_TAG = surfaceNames[1]

local function part(name: string, parent: any, tags: { string }?): any
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	for _, tag in tags or {} do
		p:AddTag(tag)
	end
	p.Parent = parent
	return p
end

local function station(name: string, tag: string, parent: any, withPrimary: boolean?): any
	local model = Instance.new("Model")
	model.Name = name
	model:AddTag(tag)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local base = part("Base", model)
	if withPrimary ~= false then
		model.PrimaryPart = base
	end
	model.Parent = parent
	return model
end

-- A zone area that meets every structure rule.
local function goodZone(zoneIndex: number): any
	local root = Instance.new("Folder")
	root.Name = string.format("Zone%02d", zoneIndex)
	root:SetAttribute("ZoneIndex", zoneIndex)
	part("Ground", root, { SURFACE_TAG })
	local start = Instance.new("Attachment")
	start.Name = "Start"
	start:AddTag("ZoneStart")
	start.Parent = root:FindFirstChild("Ground")
	local multiPart = Instance.new("Model")
	multiPart.Name = "MultiPartObstacle"
	multiPart.Parent = root
	part("PartA", multiPart, { "Obstacle" })
	part("PartB", multiPart, { "Obstacle" })
	local single = part("SingleObstacle", root, { "Obstacle" })
	single:SetAttribute("KnockOverSize", 4)
	part("Find1", root, { "FindPoint" })
	station("Stand", "UpgradeStand", root)
	local bounds = Instance.new("Folder")
	bounds.Name = Map.ZoneContract.BoundsFolderName
	bounds.Parent = root
	local wall = part("WallLeft", bounds)
	wall.Transparency = 1
	wall.CanCollide = true
	return root
end

local function hasProblem(problems: { string }, needle: string): boolean
	for _, text in problems do
		if string.find(text, needle, 1, true) then
			return true
		end
	end
	return false
end

local function expectProblem(root: any, needle: string, rules: ZoneContract.Rules?)
	local problems = ZoneContract.check(root, nil, rules or NO_COUNTS)
	T.isTrue(hasProblem(problems, needle), `expected a problem with "{needle}", got: {table.concat(problems, " | ")}`)
end

-- Every zone area file in the repository, as { world, file, zone, root }.
local function zoneFiles(): { { world: string, file: string, zone: number, roots: { any } } }
	local found = {}
	for _, world in fs.readDir("world") do
		local dir = `world/{world}`
		if not fs.isDir(dir) then
			continue
		end
		local files = fs.readDir(dir)
		table.sort(files)
		for _, file in files do
			local zone = ZoneContract.fileZone(file)
			if zone then
				local roots = roblox.deserializeModel(fs.readFile(`{dir}/{file}`))
				table.insert(found, { world = world, file = file, zone = zone, roots = roots })
			end
		end
	end
	return found
end

return T.suite("tests/world/ZoneContract", function(test)
	test("a zone that follows ADR 0009 has no problems", function()
		local problems = ZoneContract.check(goodZone(3), 3, NO_COUNTS)
		T.equal(#problems, 0, table.concat(problems, " | "))
	end)

	test("root: ZoneIndex missing, out of range, on a child or not matching the file", function()
		local root = goodZone(3)
		root:SetAttribute("ZoneIndex", nil)
		expectProblem(root, "must be a whole number")
		root:SetAttribute("ZoneIndex", 51)
		expectProblem(root, "must be a whole number")
		root:SetAttribute("ZoneIndex", 2.5)
		expectProblem(root, "must be a whole number")

		local child = goodZone(3)
		child:FindFirstChild("SingleObstacle"):SetAttribute("ZoneIndex", 3)
		expectProblem(child, "only belongs on the zone area root")

		local named = goodZone(3)
		local problems = ZoneContract.check(named, 4, NO_COUNTS)
		T.isTrue(hasProblem(problems, "does not match the file name"), "file name check")
	end)

	test("root: an atomic Model root is refused, a default Model root is fine", function()
		local model = Instance.new("Model")
		model.Name = "Zone03"
		for _, child in goodZone(3):GetChildren() do
			child.Parent = model
		end
		model:SetAttribute("ZoneIndex", 3)
		T.equal(#ZoneContract.check(model, 3, NO_COUNTS), 0, "default streaming mode")
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		expectProblem(model, "must not use ModelStreamingMode Atomic")
	end)

	test("ZoneStart: none or two is a problem, a Model is the wrong kind", function()
		local none = goodZone(1)
		none:FindFirstChild("Ground"):FindFirstChild("Start"):Destroy()
		expectProblem(none, "needs exactly 1 ZoneStart, has 0")

		local two = goodZone(1)
		part("Start2", two, { "ZoneStart" })
		expectProblem(two, "needs exactly 1 ZoneStart, has 2")

		local wrong = goodZone(1)
		wrong:FindFirstChild("Ground"):FindFirstChild("Start"):Destroy()
		local model = Instance.new("Model")
		model:AddTag("ZoneStart")
		model.Parent = wrong
		expectProblem(wrong, "ZoneStart must be an Attachment or BasePart")
	end)

	test("stations need a Model, a PrimaryPart and Atomic streaming", function()
		local noPrimary = goodZone(1)
		station("Egg", "EggStation", noPrimary, false)
		expectProblem(noPrimary, "needs a PrimaryPart")

		local streaming = goodZone(1)
		streaming:FindFirstChild("Stand").ModelStreamingMode = Enum.ModelStreamingMode.Default
		expectProblem(streaming, "needs ModelStreamingMode Atomic")

		local notModel = goodZone(1)
		part("Gate", notModel, { "Barrier" })
		expectProblem(notModel, "Barrier must be a Model")
	end)

	test("parts: surfaces and obstacles must be BaseParts, KnockOverSize positive", function()
		local root = goodZone(1)
		local attachment = Instance.new("Attachment")
		attachment:AddTag(SURFACE_TAG)
		attachment.Parent = root:FindFirstChild("Ground")
		expectProblem(root, `{SURFACE_TAG} must be a BasePart`)

		local size = goodZone(1)
		size:FindFirstChild("SingleObstacle"):SetAttribute("KnockOverSize", -1)
		expectProblem(size, "KnockOverSize must be a positive number")
	end)

	test("bounds: folder required, walls invisible, colliding and anchored", function()
		local missing = goodZone(1)
		missing:FindFirstChild(Map.ZoneContract.BoundsFolderName):Destroy()
		expectProblem(missing, "folder with the invisible walls")

		local visible = goodZone(1)
		visible:FindFirstChild(Map.ZoneContract.BoundsFolderName):FindFirstChild("WallLeft").Transparency = 0
		expectProblem(visible, "wall must be Transparency 1")

		local empty = goodZone(1)
		empty:FindFirstChild(Map.ZoneContract.BoundsFolderName):FindFirstChild("WallLeft"):Destroy()
		expectProblem(empty, "has no wall parts")
	end)

	test("counts are per object and only for configured tags", function()
		-- MultiPartObstacle (2 obstacle parts) + SingleObstacle = 2 obstacle objects.
		local root = goodZone(1)
		T.equal(#ZoneContract.check(root, nil, { Counts = { Obstacle = { Min = 2, Max = 2 } } }), 0)
		expectProblem(root, "Obstacle objects: 2, needs at least 3", { Counts = { Obstacle = { Min = 3 } } })
		expectProblem(root, "Obstacle objects: 2, allows at most 1", { Counts = { Obstacle = { Max = 1 } } })
		expectProblem(root, "FindPoint objects: 1, needs at least 2", { Counts = { FindPoint = { Min = 2 } } })
	end)

	test("knock-over share counts objects that can be knocked over", function()
		-- SingleObstacle can be knocked over, MultiPartObstacle cannot: share 0.5.
		local root = goodZone(1)
		T.equal(#ZoneContract.check(root, nil, { Counts = {}, KnockOverShare = { Min = 0.5, Max = 0.5 } }), 0)
		expectProblem(root, "knock-over share", { Counts = {}, KnockOverShare = { Min = 0.6 } })
	end)

	test("world: two areas with the same ZoneIndex", function()
		local problems = ZoneContract.checkWorld({ goodZone(2), goodZone(2) })
		T.equal(#problems, 1)
		T.equal(#ZoneContract.checkWorld({ goodZone(1), goodZone(2) }), 0)
	end)

	test("config: counts and per-world overrides are well formed", function()
		local contract = Map.ZoneContract
		T.isTrue(table.isfrozen(contract), "ZoneContract is frozen")
		for _, rules in { ZoneContract.rulesFor("") } do
			for tag, range in rules.Counts do
				T.isTrue(range.Min == nil or range.Max == nil or range.Min <= range.Max, `{tag} Min <= Max`)
			end
		end
		for world in contract.Worlds do
			T.isTrue(fs.isDir(`world/{world}`), `Worlds.{world} names a folder in world/`)
		end
	end)

	test("every ZoneNN.rbxmx in world/ meets the contract", function()
		local byWorld: { [string]: { any } } = {}
		local problems: { string } = {}
		for _, entry in zoneFiles() do
			if #entry.roots ~= 1 then
				table.insert(problems, `world/{entry.world}/{entry.file}: needs exactly 1 root, has {#entry.roots}`)
				continue
			end
			local root = entry.roots[1]
			for _, text in ZoneContract.check(root, entry.zone, ZoneContract.rulesFor(entry.world)) do
				table.insert(problems, `world/{entry.world}/{entry.file}: {text}`)
			end
			byWorld[entry.world] = byWorld[entry.world] or {}
			table.insert(byWorld[entry.world], root)
		end
		for world, roots in byWorld do
			for _, text in ZoneContract.checkWorld(roots) do
				table.insert(problems, `world/{world}: {text}`)
			end
		end
		T.equal(#problems, 0, "\n    " .. table.concat(problems, "\n    "))
	end)
end)

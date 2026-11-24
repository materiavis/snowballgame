--!strict
-- Zone check (tools/world/ZoneContract.luau). Part 1 proves the check with invented rules and
-- invented names, so it is tested without any game. Part 2 checks every
-- world/<world>/ZoneNN.rbxmx in this repository against this game's Config.WorldRules.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local T = require("../TestKit")
local ZoneContract = require("../../tools/world/ZoneContract")
local GameRules = require("../../src/shared/Config/WorldRules")

local Instance = roblox.Instance
local Enum = roblox.Enum

-- Invented rules: no game uses these names.
local RULES: ZoneContract.Rules = {
	ZoneFilePattern = "^Zone(%d%d)%.rbxmx$",
	ZoneNumberAttribute = "ZoneNumber",
	MaxZoneNumber = 50,
	BoundsFolder = "Bounds",
	StartTag = "TagStart",
	TagKinds = { TagStart = "Point", TagPoint = "Point", TagPart = "Part", TagGroup = "Group", TagGroup2 = "Group" },
	GroupStreamingMode = "Atomic",
	PositiveAttributes = { { Tag = "TagPart", Attribute = "Strength" } },
	Counts = {},
	Shares = {},
	Worlds = {},
}
local NO_LIMITS: ZoneContract.Limits = {}

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

local function group(name: string, tag: string, parent: any, withPrimary: boolean?): any
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

-- A zone that follows every rule.
local function goodZone(number: number): any
	local root = Instance.new("Folder")
	root.Name = string.format("Zone%02d", number)
	root:SetAttribute("ZoneNumber", number)
	local ground = part("Ground", root)
	local start = Instance.new("Attachment")
	start.Name = "Start"
	start:AddTag("TagStart")
	start.Parent = ground
	local multi = Instance.new("Model")
	multi.Name = "TwoPartObject"
	multi.Parent = root
	part("PartA", multi, { "TagPart" })
	part("PartB", multi, { "TagPart" })
	local single = part("OnePartObject", root, { "TagPart" })
	single:SetAttribute("Strength", 4)
	part("PointPart", root, { "TagPoint" })
	group("GroupA", "TagGroup", root)
	local bounds = Instance.new("Folder")
	bounds.Name = "Bounds"
	bounds.Parent = root
	local wall = part("Wall", bounds)
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

local function expectProblem(root: any, needle: string, limits: ZoneContract.Limits?)
	local problems = ZoneContract.check(root, nil, RULES, limits or NO_LIMITS)
	T.isTrue(hasProblem(problems, needle), `expected "{needle}", got: {table.concat(problems, " | ")}`)
end

return T.suite("tests/world/ZoneContract", function(test)
	test("a zone that follows the rules has no problems", function()
		local problems = ZoneContract.check(goodZone(3), 3, RULES, NO_LIMITS)
		T.equal(#problems, 0, table.concat(problems, " | "))
	end)

	test("zone number: missing, out of range, not whole, on a child, not matching the file", function()
		local root = goodZone(3)
		root:SetAttribute("ZoneNumber", nil)
		expectProblem(root, "must be a whole number")
		root:SetAttribute("ZoneNumber", 51)
		expectProblem(root, "must be a whole number")
		root:SetAttribute("ZoneNumber", 2.5)
		expectProblem(root, "must be a whole number")

		local child = goodZone(3)
		child:FindFirstChild("OnePartObject"):SetAttribute("ZoneNumber", 3)
		expectProblem(child, "only belongs on the zone root")

		T.isTrue(hasProblem(ZoneContract.check(goodZone(3), 4, RULES, NO_LIMITS), "does not match the file name"))
	end)

	test("zone root: an atomic Model is refused, a normal Model is fine", function()
		local model = Instance.new("Model")
		model.Name = "Zone03"
		for _, child in goodZone(3):GetChildren() do
			child.Parent = model
		end
		model:SetAttribute("ZoneNumber", 3)
		T.equal(#ZoneContract.check(model, 3, RULES, NO_LIMITS), 0)
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		expectProblem(model, "must not use ModelStreamingMode Atomic")
	end)

	test("start: none or two is a problem, a Model is the wrong kind", function()
		local none = goodZone(1)
		none:FindFirstChild("Ground"):FindFirstChild("Start"):Destroy()
		expectProblem(none, "needs exactly 1 TagStart, has 0")

		local two = goodZone(1)
		part("Start2", two, { "TagStart" })
		expectProblem(two, "needs exactly 1 TagStart, has 2")

		local wrong = goodZone(1)
		wrong:FindFirstChild("Ground"):FindFirstChild("Start"):Destroy()
		local model = Instance.new("Model")
		model:AddTag("TagStart")
		model.Parent = wrong
		expectProblem(wrong, "TagStart must be an Attachment or BasePart")
	end)

	test("kinds: Part needs a BasePart, Group needs Model, PrimaryPart and streaming mode", function()
		local onAttachment = goodZone(1)
		local attachment = Instance.new("Attachment")
		attachment:AddTag("TagPart")
		attachment.Parent = onAttachment:FindFirstChild("Ground")
		expectProblem(onAttachment, "TagPart must be a BasePart")

		local noPrimary = goodZone(1)
		group("GroupB", "TagGroup2", noPrimary, false)
		expectProblem(noPrimary, "needs a PrimaryPart")

		local streaming = goodZone(1)
		streaming:FindFirstChild("GroupA").ModelStreamingMode = Enum.ModelStreamingMode.Default
		expectProblem(streaming, "needs ModelStreamingMode Atomic")

		local notModel = goodZone(1)
		part("GroupAsPart", notModel, { "TagGroup2" })
		expectProblem(notModel, "TagGroup2 must be a Model")
	end)

	test("positive attributes: a negative value is a problem", function()
		local root = goodZone(1)
		root:FindFirstChild("OnePartObject"):SetAttribute("Strength", -1)
		expectProblem(root, "Strength must be a positive number")
	end)

	test("walls: folder needed, walls invisible, colliding and anchored", function()
		local missing = goodZone(1)
		missing:FindFirstChild("Bounds"):Destroy()
		expectProblem(missing, "folder with the invisible walls")

		local visible = goodZone(1)
		visible:FindFirstChild("Bounds"):FindFirstChild("Wall").Transparency = 0
		expectProblem(visible, "wall must be Transparency 1")

		local empty = goodZone(1)
		empty:FindFirstChild("Bounds"):FindFirstChild("Wall"):Destroy()
		expectProblem(empty, "has no wall parts")
	end)

	test("counts are per object: a Model with two tagged parts counts once", function()
		local root = goodZone(1)
		T.equal(#ZoneContract.check(root, nil, RULES, { Counts = { TagPart = { Min = 2, Max = 2 } } }), 0)
		expectProblem(root, "TagPart objects: 2, needs at least 3", { Counts = { TagPart = { Min = 3 } } })
		expectProblem(root, "TagPart objects: 2, allows at most 1", { Counts = { TagPart = { Max = 1 } } })
	end)

	test("shares: OnePartObject has Strength, TwoPartObject not, so the share is 0.5", function()
		local root = goodZone(1)
		local half = { Tag = "TagPart", Attribute = "Strength", Min = 0.5, Max = 0.5 }
		T.equal(#ZoneContract.check(root, nil, RULES, { Shares = { half } }), 0)
		local more = { Tag = "TagPart", Attribute = "Strength", Min = 0.6 }
		expectProblem(root, "share of TagPart with Strength", { Shares = { more } })
	end)

	test("world: two zones with the same number", function()
		T.equal(#ZoneContract.checkWorld({ goodZone(2), goodZone(2) }, RULES), 1)
		T.equal(#ZoneContract.checkWorld({ goodZone(1), goodZone(2) }, RULES), 0)
	end)

	test("world limits replace the general ones", function()
		local rules = table.clone(RULES)
		rules.Counts = { TagPart = { Min = 1 } }
		rules.Worlds = { forest = { Counts = { TagPoint = { Min = 1 } } } }
		T.isTrue(ZoneContract.limitsFor(rules, "forest").Counts.TagPoint ~= nil)
		T.isTrue(ZoneContract.limitsFor(rules, "other").Counts.TagPart ~= nil)
	end)

	test("every ZoneNN.rbxmx in world/ follows this game's world rules", function()
		local rules = GameRules :: any
		local byWorld: { [string]: { any } } = {}
		local problems: { string } = {}
		for _, world in fs.readDir("world") do
			local dir = `world/{world}`
			if not fs.isDir(dir) then
				continue
			end
			for _, file in fs.readDir(dir) do
				local zone = ZoneContract.fileZone(rules, file)
				if not zone then
					continue
				end
				local roots = roblox.deserializeModel(fs.readFile(`{dir}/{file}`))
				if #roots ~= 1 then
					table.insert(problems, `{dir}/{file}: needs exactly 1 root, has {#roots}`)
					continue
				end
				for _, text in ZoneContract.check(roots[1], zone, rules, ZoneContract.limitsFor(rules, world)) do
					table.insert(problems, `{dir}/{file}: {text}`)
				end
				byWorld[world] = byWorld[world] or {}
				table.insert(byWorld[world], roots[1])
			end
		end
		for world, roots in byWorld do
			for _, text in ZoneContract.checkWorld(roots, rules) do
				table.insert(problems, `world/{world}: {text}`)
			end
		end
		T.equal(#problems, 0, "\n    " .. table.concat(problems, "\n    "))
	end)
end)

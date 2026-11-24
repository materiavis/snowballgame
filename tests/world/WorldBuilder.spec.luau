--!strict
-- World builder (tools/world/Builder.luau): from a plan to a zone file, with invented rules,
-- an invented kit and invented names, in a temporary folder under build/.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local T = require("../TestKit")
local Builder = require("../../tools/world/Builder")
local ZoneContract = require("../../tools/world/ZoneContract")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Enum = roblox.Enum

local TMP = "build/tmp-world-builder"

local RULES: ZoneContract.Rules = {
	ZoneFilePattern = "^Zone(%d%d)%.rbxmx$",
	ZoneNumberAttribute = "ZoneNumber",
	MaxZoneNumber = 50,
	BoundsFolder = "Bounds",
	StartTag = "TagStart",
	TagKinds = { TagStart = "Point", TagPart = "Part", TagGroup = "Group" },
	GroupStreamingMode = "Atomic",
	PositiveAttributes = {},
	Counts = {},
	Shares = {},
	Worlds = {},
}

-- A kit with a block (scalable 0.5-2, one tagged part) and a group (a station-like Model).
local function kitContents(): string
	local folder = Instance.new("Folder")
	folder.Name = "TestKit"
	local block = Instance.new("Model")
	block.Name = "Block"
	block:SetAttribute("ScaleMin", 0.5)
	block:SetAttribute("ScaleMax", 2)
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(4, 2, 4)
	base.CFrame = CFrame.new(0, 1, 0)
	base:AddTag("TagPart")
	base.Parent = block
	local top = Instance.new("Part")
	top.Name = "Top"
	top.Size = Vector3.new(2, 2, 2)
	top.CFrame = CFrame.new(0, 3, 0)
	top.Parent = block
	block.PrimaryPart = base
	block.Parent = folder
	local groupModel = Instance.new("Model")
	groupModel.Name = "Group"
	groupModel:AddTag("TagGroup")
	groupModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local groupBase = Instance.new("Part")
	groupBase.Name = "Base"
	groupBase.Size = Vector3.new(6, 1, 6)
	groupBase.Parent = groupModel
	groupModel.PrimaryPart = groupBase
	groupModel.Parent = folder
	return roblox.serializeModel({ folder }, true)
end

local function plan(zone: number): { [string]: any }
	return {
		zone = zone,
		kit = "world/kits/test.rbxmx",
		ground = { { name = "Ground", size = { 100, 2, 100 }, position = { 0, -1, 0 }, material = "Slate" } },
		start = { 0, 1, -40 },
		bounds = { min = { -50, -50 }, max = { 50, 50 }, height = 30 },
		objects = {
			{ template = "Block", position = { 10, 0, 10 }, rotation = 90, scale = 2 },
			{ template = "Group", position = { 0, 0, 20 }, name = "MainGroup" },
		},
	}
end

local function templates(): { [string]: any }
	local kit, err = Builder.readKit(kitContents())
	assert(kit, err)
	return kit
end

local function setUp(plans: { { [string]: any } })
	if fs.isDir(TMP) then
		fs.removeDir(TMP)
	end
	fs.writeDir(`{TMP}/world/kits`)
	fs.writeDir(`{TMP}/tools/world/test`)
	fs.writeFile(`{TMP}/world/kits/test.rbxmx`, kitContents())
	for _, p in plans do
		fs.writeFile(string.format("%s/tools/world/test/Zone%02d.plan.json", TMP, p.zone), serde.encode("json", p))
	end
end

local function tearDown()
	if fs.isDir(TMP) then
		fs.removeDir(TMP)
	end
end

return T.suite("tests/world/WorldBuilder", function(test)
	test("a correct plan gives a zone that passes the zone check", function()
		local root, mistakes = Builder.buildZone(plan(1) :: any, templates(), RULES)
		T.isTrue(root ~= nil, table.concat(mistakes, " | "))
		local problems = ZoneContract.check(root, 1, RULES, {})
		T.equal(#problems, 0, table.concat(problems, " | "))
		T.equal(#root:FindFirstChild("Bounds"):GetChildren(), 4)
		T.isTrue(root:FindFirstChild("Start"):HasTag("TagStart"))
	end)

	test("objects sit on their position, turned and scaled", function()
		local root = Builder.buildZone(plan(1) :: any, templates(), RULES)
		local block = root:FindFirstChild("Objects"):FindFirstChild("Block_01")
		local base = block:FindFirstChild("Base")
		-- Scale 2: base is 4 high, so its middle is 2 above the given position.
		T.equal(base.Size.Y, 4)
		T.isTrue((base.CFrame.Position - Vector3.new(10, 2, 10)).Magnitude < 1e-4, `base at {base.CFrame.Position}`)
		-- The top keeps its place relative to the base, scaled: 2 above the base middle becomes 4.
		local top = block:FindFirstChild("Top")
		T.isTrue((top.CFrame.Position - Vector3.new(10, 6, 10)).Magnitude < 1e-4, `top at {top.CFrame.Position}`)
		T.isTrue(root:FindFirstChild("Objects"):FindFirstChild("MainGroup") ~= nil)
	end)

	test("the same plan gives the same file", function()
		local a = roblox.serializeModel({ (Builder.buildZone(plan(1) :: any, templates(), RULES)) }, true)
		local b = roblox.serializeModel({ (Builder.buildZone(plan(1) :: any, templates(), RULES)) }, true)
		T.isTrue(a == b, "two builds differ")
	end)

	test("plan mistakes are reported, nothing is built", function()
		local unknown = plan(1)
		unknown.objects = { { template = "Nope", position = { 0, 0, 0 } } }
		local root, mistakes = Builder.buildZone(unknown :: any, templates(), RULES)
		T.isTrue(root == nil and string.find(mistakes[1], "not in the kit", 1, true) ~= nil)

		local tooBig = plan(1)
		tooBig.objects = { { template = "Block", position = { 0, 0, 0 }, scale = 3 } }
		root, mistakes = Builder.buildZone(tooBig :: any, templates(), RULES)
		T.isTrue(root == nil and string.find(mistakes[1], "outside 0.5-2", 1, true) ~= nil)

		local noScale = plan(1)
		noScale.objects = { { template = "Group", position = { 0, 0, 0 }, scale = 1.5 } }
		root, mistakes = Builder.buildZone(noScale :: any, templates(), RULES)
		T.isTrue(root == nil and string.find(mistakes[1], "outside 1-1", 1, true) ~= nil)

		local badBounds = plan(1)
		badBounds.bounds = { min = { 10, 10 }, max = { 0, 0 }, height = 5 }
		root, mistakes = Builder.buildZone(badBounds :: any, templates(), RULES)
		T.isTrue(root == nil and string.find(mistakes[1], "smaller than max", 1, true) ~= nil)

		local badMaterial = plan(1)
		badMaterial.ground[1].material = "Nope"
		root, mistakes = Builder.buildZone(badMaterial :: any, templates(), RULES)
		T.isTrue(root == nil and string.find(mistakes[1], "not a Roblox material", 1, true) ~= nil)
	end)

	test("run writes the zone files and their fingerprints", function()
		setUp({ plan(1), plan(2) })
		local report = Builder.run(TMP, "test", nil, RULES)
		T.isTrue(report.ok, table.concat(report.lines, " | "))
		T.isTrue(fs.isFile(`{TMP}/world/test/Zone01.rbxmx`) and fs.isFile(`{TMP}/world/test/Zone02.rbxmx`))
		local fingerprints = serde.decode("json", fs.readFile(`{TMP}/tools/world/test/fingerprints.json`))
		T.equal(fingerprints["Zone01.rbxmx"], Builder.fingerprint(fs.readFile(`{TMP}/world/test/Zone01.rbxmx`)))
		-- Building again without changes is allowed and gives the same file.
		local before = fs.readFile(`{TMP}/world/test/Zone01.rbxmx`)
		T.isTrue(Builder.run(TMP, "test", 1, RULES).ok)
		T.isTrue(fs.readFile(`{TMP}/world/test/Zone01.rbxmx`) == before)
		tearDown()
	end)

	test("a zone changed by hand is never overwritten", function()
		setUp({ plan(1) })
		T.isTrue(Builder.run(TMP, "test", nil, RULES).ok)
		local path = `{TMP}/world/test/Zone01.rbxmx`
		local edited = fs.readFile(path) .. "\n<!-- changed in Studio -->\n"
		fs.writeFile(path, edited)
		local report = Builder.run(TMP, "test", nil, RULES)
		T.isTrue(not report.ok)
		T.isTrue(string.find(table.concat(report.lines, " "), "changed by hand", 1, true) ~= nil)
		T.isTrue(fs.readFile(path) == edited, "the edited file must stay as it is")
		tearDown()
	end)

	test("one bad plan stops the whole run, nothing is written", function()
		local bad = plan(2)
		bad.objects = { { template = "Nope", position = { 0, 0, 0 } } }
		setUp({ plan(1), bad })
		local report = Builder.run(TMP, "test", nil, RULES)
		T.isTrue(not report.ok)
		T.isTrue(not fs.isFile(`{TMP}/world/test/Zone01.rbxmx`), "zone 1 must not be written either")
		tearDown()
	end)

	test("a plan whose zone number does not match its file name is refused", function()
		local wrong = plan(1)
		wrong.zone = 5
		setUp({})
		fs.writeFile(`{TMP}/tools/world/test/Zone01.plan.json`, serde.encode("json", wrong))
		local report = Builder.run(TMP, "test", nil, RULES)
		T.isTrue(not report.ok)
		tearDown()
	end)
end)

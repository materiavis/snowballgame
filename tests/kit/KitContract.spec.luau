--!strict
-- Kit check (tools/kit/KitContract.luau). Part 1 proves the check with invented rules and
-- invented names, and that a kit that passes it builds a zone the world-builder accepts.
-- Part 2 checks every world/kits/<kit>.rbxmx in this repository against this game's
-- Config.WorldRules and its upload list tools/kit/<kit>/upload-list.json.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local T = require("../TestKit")
local KitContract = require("../../tools/kit/KitContract")
local Builder = require("../../tools/world/Builder")
local ZoneContract = require("../../tools/world/ZoneContract")
local GameRules = require("../../src/shared/Config/WorldRules")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Enum = roblox.Enum

-- Invented rules: no game uses these names. Full zone rules, so the builder can use them too.
local RULES: ZoneContract.Rules = {
	ZoneFilePattern = "^Zone(%d%d)%.rbxmx$",
	ZoneNumberAttribute = "ZoneNumber",
	MaxZoneNumber = 50,
	BoundsFolder = "Bounds",
	StartTag = "TagStart",
	TagKinds = { TagStart = "Point", TagPoint = "Point", TagPart = "Part", TagGroup = "Group" },
	GroupStreamingMode = "Atomic",
	PositiveAttributes = { { Tag = "TagPart", Attribute = "Strength" } },
	Counts = {},
	Shares = {},
	Worlds = {},
}

local UPLOADS: KitContract.Uploads = { meshIds = { [111] = true, [222] = true }, textureIds = { [333] = true } }

local function mesh(name: string, parent: any, meshId: number, textureId: number?): any
	local m = Instance.new("MeshPart")
	m.Name = name
	m.Anchored = true
	m.CanCollide = false
	m.CanQuery = false
	m.CanTouch = false
	m.MeshId = `rbxassetid://{meshId}`
	if textureId then
		m.TextureID = `rbxassetid://{textureId}`
	end
	m.Size = Vector3.new(3, 4, 3)
	m.CFrame = CFrame.new(0, 2.5, 0)
	m.Parent = parent
	return m
end

local function invisible(name: string, parent: any, size: any, position: any): any
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Transparency = 1
	p.Size = size
	p.CFrame = CFrame.new(position)
	p.Parent = parent
	return p
end

-- A kit that follows every rule: a scalable prop, an obstacle with a size attribute (not
-- scalable) and a station-like group.
local function goodKit(): any
	local folder = Instance.new("Folder")
	folder.Name = "TestKit"

	local prop = Instance.new("Model")
	prop.Name = "Prop_1"
	prop:SetAttribute("ScaleMin", 0.8)
	prop:SetAttribute("ScaleMax", 1.5)
	local propFoot = invisible("Foot", prop, Vector3.new(3, 1, 3), Vector3.new(0, 0.5, 0))
	propFoot:AddTag("TagPart")
	mesh("Look", prop, 111, 333)
	prop.PrimaryPart = propFoot
	prop.Parent = folder

	local obstacle = Instance.new("Model")
	obstacle.Name = "Obstacle_1"
	local obstacleFoot = invisible("Foot", obstacle, Vector3.new(2, 2, 2), Vector3.new(0, 1, 0))
	obstacleFoot:AddTag("TagPart")
	obstacleFoot:SetAttribute("Strength", 4)
	mesh("Look", obstacle, 222)
	obstacle.PrimaryPart = obstacleFoot
	obstacle.Parent = folder

	local group = Instance.new("Model")
	group.Name = "Group_1"
	group:AddTag("TagGroup")
	group.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local groupFoot = invisible("Foot", group, Vector3.new(6, 1, 6), Vector3.new(0, 0.5, 0))
	mesh("Look", group, 111)
	local label = Instance.new("Attachment")
	label.Name = "Label"
	label:AddTag("TagPoint")
	label.Parent = groupFoot
	group.PrimaryPart = groupFoot
	group.Parent = folder

	return folder
end

local function problemsOf(kit: any): { string }
	return KitContract.check(kit, RULES, UPLOADS)
end

local function hasProblem(problems: { string }, pattern: string): boolean
	for _, text in problems do
		if string.find(text, pattern) then
			return true
		end
	end
	return false
end

local function expectProblem(kit: any, pattern: string)
	local problems = problemsOf(kit)
	T.isTrue(
		hasProblem(problems, pattern),
		`expected a problem matching "{pattern}", got: {table.concat(problems, " | ")}`
	)
end

return T.suite("tests/kit/KitContract", function(test)
	test("a kit that follows every rule has no problems", function()
		local problems = problemsOf(goodKit())
		T.equal(#problems, 0, table.concat(problems, " | "))
	end)

	test("survives a file round trip (MeshId is read back as MeshContent)", function()
		local roots = roblox.deserializeModel(roblox.serializeModel({ goodKit() }, true))
		local problems = problemsOf(roots[1])
		T.equal(#problems, 0, table.concat(problems, " | "))
	end)

	test("a kit that passes builds a zone the world-builder and the zone check accept", function()
		local templates, kitError = Builder.readKit(roblox.serializeModel({ goodKit() }, true))
		T.isTrue(templates, kitError)
		local plan = {
			zone = 1,
			kit = "world/kits/test.rbxmx",
			ground = { { name = "Ground", size = { 60, 2, 60 }, position = { 0, -1, 0 } } },
			start = { 0, 1, -20 },
			bounds = { min = { -30, -30 }, max = { 30, 30 }, height = 20 },
			objects = {
				{ template = "Prop_1", position = { 10, 0, 10 }, rotation = 45, scale = 1.5 },
				{ template = "Obstacle_1", position = { -10, 0, 10 } },
				{ template = "Group_1", position = { 0, 0, 20 } },
			},
		}
		local zone, mistakes = Builder.buildZone(plan, templates :: any, RULES)
		T.equal(#mistakes, 0, table.concat(mistakes, " | "))
		local problems = ZoneContract.check(zone, 1, RULES, {})
		T.equal(#problems, 0, table.concat(problems, " | "))
	end)

	test("the kit root must be a Folder with templates", function()
		local model = Instance.new("Model")
		model.Name = "NotAFolder"
		T.isTrue(hasProblem(problemsOf(model), "must be a Folder"))
		local empty = Instance.new("Folder")
		empty.Name = "Empty"
		T.isTrue(hasProblem(problemsOf(empty), "no templates"))
	end)

	test("only template Models sit in the kit folder", function()
		local kit = goodKit()
		invisible("Loose", kit, Vector3.new(1, 1, 1), Vector3.new(0, 0, 0))
		expectProblem(kit, "only template Models")
	end)

	test("templates need a PrimaryPart that is not rotated", function()
		local kit = goodKit()
		local bare = Instance.new("Model")
		bare.Name = "Bare_1"
		invisible("Foot", bare, Vector3.new(1, 1, 1), Vector3.new(0, 0.5, 0))
		bare.Parent = kit
		expectProblem(kit, "Bare_1: needs a PrimaryPart")
		local turned = goodKit()
		turned.Obstacle_1.Foot.CFrame = CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(30), 0)
		expectProblem(turned, "must not be rotated")
	end)

	test("scale range must be positive and in order", function()
		local kit = goodKit()
		kit.Prop_1:SetAttribute("ScaleMin", 2)
		expectProblem(kit, "is above ScaleMax")
		local negative = goodKit()
		negative.Prop_1:SetAttribute("ScaleMax", -1)
		expectProblem(negative, "ScaleMax must be a positive number")
	end)

	test("a template with a size attribute cannot be scalable", function()
		local kit = goodKit()
		kit.Obstacle_1:SetAttribute("ScaleMax", 2)
		expectProblem(kit, "does not scale")
	end)

	test("size attributes must be positive", function()
		local kit = goodKit()
		kit.Obstacle_1.Foot:SetAttribute("Strength", 0)
		expectProblem(kit, "Strength must be a positive number")
	end)

	test("tags sit on the kind of object the rules ask for, never on the mesh", function()
		local kit = goodKit()
		kit.Prop_1:AddTag("TagPart")
		expectProblem(kit, "TagPart must be a BasePart")
		local onMesh = goodKit()
		onMesh.Prop_1.Look:AddTag("TagPart")
		expectProblem(onMesh, "not on the mesh")
		local loose = goodKit()
		loose.Group_1.ModelStreamingMode = Enum.ModelStreamingMode.Default
		expectProblem(loose, "needs ModelStreamingMode Atomic")
	end)

	test("start tags and zone numbers are the world-builder's", function()
		local kit = goodKit()
		kit.Prop_1.Foot:AddTag("TagStart")
		expectProblem(kit, "placed by the world%-builder")
		local numbered = goodKit()
		numbered.Prop_1:SetAttribute("ZoneNumber", 1)
		expectProblem(numbered, "belongs on the zone root")
	end)

	test("the mesh is only the look", function()
		local kit = goodKit()
		kit.Prop_1.Look.CanCollide = true
		expectProblem(kit, "CanCollide, CanQuery and CanTouch off")
		local visible = goodKit()
		visible.Prop_1.Foot.Transparency = 0
		expectProblem(visible, "Transparency 1 and Anchored")
	end)

	test("asset ids only from the upload list", function()
		local kit = goodKit()
		kit.Prop_1.Look.MeshId = "rbxassetid://999"
		expectProblem(kit, "MeshId rbxassetid://999 is not in the upload list")
		local texture = goodKit()
		texture.Prop_1.Look.TextureID = "rbxassetid://998"
		expectProblem(texture, "TextureID rbxassetid://998 is not in the upload list")
		local web = goodKit()
		web.Prop_1.Look.MeshId = "http://example.invalid/mesh"
		expectProblem(web, "is not in the upload list")
		local missing = Instance.new("MeshPart")
		missing.Name = "NoId"
		missing.Anchored = true
		missing.CanCollide = false
		missing.CanQuery = false
		missing.CanTouch = false
		local withMissing = goodKit()
		missing.Parent = withMissing.Prop_1
		expectProblem(withMissing, "waiting for upload")
	end)

	test("no scripts and no SpecialMesh", function()
		local kit = goodKit()
		Instance.new("Script").Parent = kit.Prop_1
		expectProblem(kit, "no scripts")
		local special = goodKit()
		Instance.new("SpecialMesh").Parent = special.Prop_1.Foot
		expectProblem(special, "use a MeshPart")
	end)

	test("upload list format", function()
		local uploads = KitContract.uploadsFrom({ Rock_1 = { meshId = 5, textureId = 6 }, Rock_2 = { meshId = 7 } })
		T.isTrue(uploads and uploads.meshIds[5] and uploads.meshIds[7] and uploads.textureIds[6])
		local _, wrongId = KitContract.uploadsFrom({ Rock_1 = { meshId = "rbxassetid://5" } })
		T.isTrue(wrongId and string.find(wrongId, "meshId"))
		local _, notObject = KitContract.uploadsFrom("[]")
		T.isTrue(notObject)
	end)

	test("every kit in world/kits follows this game's world rules and upload list", function()
		local dir = "world/kits"
		if not fs.isDir(dir) then
			return
		end
		local problems: { string } = {}
		for _, file in fs.readDir(dir) do
			local kitName = string.match(file, "^(.+)%.rbxmx$")
			if not kitName then
				continue
			end
			local uploads: KitContract.Uploads = { meshIds = {}, textureIds = {} }
			local listPath = `tools/kit/{kitName}/upload-list.json`
			if fs.isFile(listPath) then
				local decoded, listError = KitContract.uploadsFrom(serde.decode("json", fs.readFile(listPath)))
				if not decoded then
					table.insert(problems, `{listPath}: {listError}`)
					continue
				end
				uploads = decoded
			end
			local roots = roblox.deserializeModel(fs.readFile(`{dir}/{file}`))
			if #roots ~= 1 then
				table.insert(problems, `{dir}/{file}: must hold exactly one Folder, holds {#roots} roots`)
				continue
			end
			for _, text in KitContract.check(roots[1], GameRules :: any, uploads) do
				table.insert(problems, `{dir}/{file}: {text}`)
			end
		end
		T.equal(#problems, 0, table.concat(problems, "\n"))
	end)
end)

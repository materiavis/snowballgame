--!strict
-- World builder: turns zone plans (what stands where) into zone files (.rbxmx). General for
-- every game: it knows no tag name; names come from the game's world rules.
-- Plan format, kit format and the flow: tools/world/README.md.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local ZoneContract = require("./ZoneContract")

local Builder = {}

export type Vec = { number }
export type GroundPiece = {
	name: string?,
	size: Vec,
	position: Vec,
	material: string?,
	color: Vec?,
	tags: { string }?,
}
export type ObjectEntry = {
	template: string,
	position: Vec,
	rotation: number?,
	scale: number?,
	name: string?,
}
export type Plan = {
	zone: number,
	kit: string,
	ground: { GroundPiece },
	start: Vec,
	bounds: { min: Vec, max: Vec, bottom: number?, height: number },
	objects: { ObjectEntry }?,
}

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local Enum = roblox.Enum

local WALL_THICKNESS = 2

local function isVec(value: any, length: number): boolean
	if type(value) ~= "table" or #value ~= length then
		return false
	end
	for _, n in value do
		if type(n) ~= "number" or n ~= n or math.abs(n) == math.huge then
			return false
		end
	end
	return true
end

local function vec3(v: Vec): any
	return Vector3.new(v[1], v[2], v[3])
end

local function anchoredPart(name: string, size: any, position: any): any
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = CFrame.new(position)
	return part
end

-- Moves (and scales) a copied template so the middle of its base's underside sits on `target`.
local function place(model: any, position: any, rotationDegrees: number, scale: number)
	local base = model.PrimaryPart
	local pivot = base.CFrame
	local lift = Vector3.new(0, base.Size.Y * scale / 2, 0)
	local target = CFrame.new(position + lift) * CFrame.Angles(0, math.rad(rotationDegrees), 0)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local relative = pivot:Inverse() * item.CFrame
			local rotation = relative - relative.Position
			item.CFrame = target * CFrame.new(relative.Position * scale) * rotation
			item.Size = item.Size * scale
		elseif item:IsA("Attachment") then
			local rotation = item.CFrame - item.CFrame.Position
			item.CFrame = CFrame.new(item.CFrame.Position * scale) * rotation
		end
	end
end

-- The templates of a kit by name, from the kit file's contents.
function Builder.readKit(contents: string): ({ [string]: any }?, string?)
	local roots = roblox.deserializeModel(contents)
	if #roots ~= 1 or not roots[1]:IsA("Folder") then
		return nil, "kit must hold exactly one Folder"
	end
	local templates = {}
	for _, child in roots[1]:GetChildren() do
		if child:IsA("Model") then
			if not child.PrimaryPart then
				return nil, `kit template {child.Name} has no PrimaryPart`
			end
			if templates[child.Name] then
				return nil, `kit has two templates named {child.Name}`
			end
			templates[child.Name] = child
		end
	end
	return templates, nil
end

-- Builds one zone from a plan. Returns the zone root, or nil and the list of plan mistakes.
function Builder.buildZone(plan: Plan, templates: { [string]: any }, rules: any): (any?, { string })
	local mistakes: { string } = {}
	local function mistake(text: string)
		table.insert(mistakes, text)
	end

	if type(plan.zone) ~= "number" or plan.zone % 1 ~= 0 then
		mistake("zone must be a whole number")
	end
	if type(plan.ground) ~= "table" or #plan.ground == 0 then
		mistake("ground needs at least one piece")
	end
	if not isVec(plan.start, 3) then
		mistake("start must be [x, y, z]")
	end
	local bounds = plan.bounds
	if
		type(bounds) ~= "table"
		or not isVec(bounds.min, 2)
		or not isVec(bounds.max, 2)
		or type(bounds.height) ~= "number"
		or bounds.height <= 0
	then
		mistake("bounds needs min [x, z], max [x, z] and a height above 0")
	elseif bounds.min[1] >= bounds.max[1] or bounds.min[2] >= bounds.max[2] then
		mistake("bounds min must be smaller than max")
	end
	if #mistakes > 0 then
		return nil, mistakes
	end

	local root = Instance.new("Folder")
	root.Name = string.format("Zone%02d", plan.zone)
	root:SetAttribute(rules.ZoneNumberAttribute, plan.zone)

	-- Ground: own geometry, the only thing the builder shapes itself.
	local groundFolder = Instance.new("Folder")
	groundFolder.Name = "Ground"
	groundFolder.Parent = root
	for i, piece in plan.ground do
		if not isVec(piece.size, 3) or not isVec(piece.position, 3) then
			mistake(`ground[{i}] needs size and position as [x, y, z]`)
			continue
		end
		local part = anchoredPart(piece.name or `Ground{i}`, vec3(piece.size), vec3(piece.position))
		if piece.material then
			local ok, material = pcall(function()
				return (Enum.Material :: any)[piece.material]
			end)
			if ok then
				part.Material = material
			else
				mistake(`ground[{i}] material {piece.material} is not a Roblox material`)
			end
		end
		if piece.color then
			if isVec(piece.color, 3) then
				part.Color = Color3.fromRGB(piece.color[1], piece.color[2], piece.color[3])
			else
				mistake(`ground[{i}] color must be [r, g, b]`)
			end
		end
		for _, tag in piece.tags or {} do
			part:AddTag(tag)
		end
		part.Parent = groundFolder
	end

	-- Start: one small invisible part with the start tag.
	local start = anchoredPart("Start", Vector3.new(1, 1, 1), vec3(plan.start))
	start.Transparency = 1
	start.CanCollide = false
	start.CanQuery = false
	start.CanTouch = false
	start:AddTag(rules.StartTag)
	start.Parent = root

	-- Objects: copies of kit templates.
	local objectsFolder = Instance.new("Folder")
	objectsFolder.Name = "Objects"
	objectsFolder.Parent = root
	local usedNames: { [string]: boolean } = {}
	for i, entry in plan.objects or {} do
		local template = templates[entry.template]
		if not template then
			mistake(`objects[{i}] template {entry.template} is not in the kit`)
			continue
		end
		if not isVec(entry.position, 3) then
			mistake(`objects[{i}] position must be [x, y, z]`)
			continue
		end
		local scale = entry.scale or 1
		local scaleMin = template:GetAttribute("ScaleMin") or 1
		local scaleMax = template:GetAttribute("ScaleMax") or 1
		if type(scale) ~= "number" or scale < scaleMin or scale > scaleMax then
			mistake(`objects[{i}] scale {scale} is outside {scaleMin}-{scaleMax} of {entry.template}`)
			continue
		end
		local name = entry.name or string.format("%s_%02d", entry.template, i)
		if usedNames[name] then
			mistake(`objects[{i}] name {name} is used twice`)
			continue
		end
		usedNames[name] = true
		local copy = template:Clone()
		copy.Name = name
		place(copy, vec3(entry.position), entry.rotation or 0, scale)
		copy.Parent = objectsFolder
	end

	-- Bounds: four invisible walls around the rectangle min..max.
	local boundsFolder = Instance.new("Folder")
	boundsFolder.Name = rules.BoundsFolder
	boundsFolder.Parent = root
	local minX, minZ = bounds.min[1], bounds.min[2]
	local maxX, maxZ = bounds.max[1], bounds.max[2]
	local bottom = bounds.bottom or 0
	local height = bounds.height
	local midY = bottom + height / 2
	local width, depth = maxX - minX, maxZ - minZ
	local walls = {
		{
			"WallNorth",
			Vector3.new(width + 2 * WALL_THICKNESS, height, WALL_THICKNESS),
			Vector3.new((minX + maxX) / 2, midY, maxZ + WALL_THICKNESS / 2),
		},
		{
			"WallSouth",
			Vector3.new(width + 2 * WALL_THICKNESS, height, WALL_THICKNESS),
			Vector3.new((minX + maxX) / 2, midY, minZ - WALL_THICKNESS / 2),
		},
		{
			"WallEast",
			Vector3.new(WALL_THICKNESS, height, depth),
			Vector3.new(maxX + WALL_THICKNESS / 2, midY, (minZ + maxZ) / 2),
		},
		{
			"WallWest",
			Vector3.new(WALL_THICKNESS, height, depth),
			Vector3.new(minX - WALL_THICKNESS / 2, midY, (minZ + maxZ) / 2),
		},
	}
	for _, wall in walls do
		local part = anchoredPart(wall[1], wall[2], wall[3])
		part.Transparency = 1
		part.CanCollide = true
		part.Parent = boundsFolder
	end

	if #mistakes > 0 then
		return nil, mistakes
	end
	return root, mistakes
end

-- The fingerprint of a zone file: changes when anything in the file changes.
function Builder.fingerprint(contents: string): string
	return serde.hash("sha256", contents)
end

-- Fingerprints as JSON with sorted keys, so the same zones give the same file.
function Builder.encodeFingerprints(fingerprints: { [string]: string }): string
	local names = {}
	for name in fingerprints do
		table.insert(names, name)
	end
	table.sort(names)
	local lines = {}
	for _, name in names do
		table.insert(lines, `  "{name}": "{fingerprints[name]}"`)
	end
	return "{\n" .. table.concat(lines, ",\n") .. "\n}\n"
end

export type Report = { ok: boolean, lines: { string } }

-- Builds the zones of one world from their plans and writes them, but only when every plan is
-- correct and every zone passes the zone check. Nothing is written otherwise. A zone file whose
-- fingerprint differs from the last build was changed by hand: it is never overwritten.
-- `baseDir` is the repository root (tests use a temporary folder). `onlyZone` builds one zone.
function Builder.run(baseDir: string, world: string, onlyZone: number?, rules: any): Report
	local lines: { string } = {}
	local ok = true
	local function fail(text: string)
		ok = false
		table.insert(lines, "FAIL " .. text)
	end

	local planDir = `{baseDir}/tools/world/{world}`
	local zoneDir = `{baseDir}/world/{world}`
	local fingerprintFile = `{planDir}/fingerprints.json`
	if not fs.isDir(planDir) then
		fail(`no plan folder tools/world/{world}`)
		return { ok = false, lines = lines }
	end
	local fingerprints: { [string]: string } = if fs.isFile(fingerprintFile)
		then serde.decode("json", fs.readFile(fingerprintFile))
		else {}

	local planFiles = {}
	for _, file in fs.readDir(planDir) do
		local digits = string.match(file, "^Zone(%d%d)%.plan%.json$")
		if digits and (onlyZone == nil or tonumber(digits) == onlyZone) then
			table.insert(planFiles, file)
		end
	end
	table.sort(planFiles)
	if #planFiles == 0 then
		fail(`no zone plans in tools/world/{world}` .. (if onlyZone then ` for zone {onlyZone}` else ""))
		return { ok = false, lines = lines }
	end

	local kits: { [string]: { [string]: any } } = {}
	local built: { { file: string, contents: string, root: any } } = {}
	for _, planFile in planFiles do
		local zoneFile = (string.gsub(planFile, "%.plan%.json$", ".rbxmx"))
		local okDecode, plan = pcall(serde.decode, "json" :: any, fs.readFile(`{planDir}/{planFile}`))
		if not okDecode then
			fail(`{planFile}: not valid JSON ({plan})`)
			continue
		end
		if plan.zone ~= tonumber(string.match(planFile, "%d%d")) then
			fail(`{planFile}: "zone" is {plan.zone}, the file name says {string.match(planFile, "%d%d")}`)
			continue
		end

		-- Never overwrite a zone changed by hand.
		local zonePath = `{zoneDir}/{zoneFile}`
		if fs.isFile(zonePath) then
			local known = fingerprints[zoneFile]
			if known == nil or known ~= Builder.fingerprint(fs.readFile(zonePath)) then
				fail(`{zoneFile}: changed by hand or not built by the builder, left untouched`)
				continue
			end
		end

		local kitPath = plan.kit
		if type(kitPath) ~= "string" or not fs.isFile(`{baseDir}/{kitPath}`) then
			fail(`{planFile}: kit {kitPath} not found`)
			continue
		end
		if not kits[kitPath] then
			local templates, kitError = Builder.readKit(fs.readFile(`{baseDir}/{kitPath}`))
			if not templates then
				fail(`{kitPath}: {kitError}`)
				continue
			end
			kits[kitPath] = templates
		end

		local root, mistakes = Builder.buildZone(plan, kits[kitPath], rules)
		if not root then
			for _, text in mistakes do
				fail(`{planFile}: {text}`)
			end
			continue
		end
		local problems = ZoneContract.check(root, plan.zone, rules, ZoneContract.limitsFor(rules, world))
		if #problems > 0 then
			for _, text in problems do
				fail(`{zoneFile}: {text}`)
			end
			continue
		end
		table.insert(built, { file = zoneFile, contents = roblox.serializeModel({ root }, true), root = root })
	end

	if not ok then
		table.insert(lines, "Nothing was written.")
		return { ok = false, lines = lines }
	end

	if not fs.isDir(zoneDir) then
		fs.writeDir(zoneDir)
	end
	for _, zone in built do
		fs.writeFile(`{zoneDir}/{zone.file}`, zone.contents)
		fingerprints[zone.file] = Builder.fingerprint(zone.contents)
		table.insert(lines, `OK   world/{world}/{zone.file}`)
	end
	fs.writeFile(fingerprintFile, Builder.encodeFingerprints(fingerprints))
	return { ok = true, lines = lines }
end

return table.freeze(Builder)

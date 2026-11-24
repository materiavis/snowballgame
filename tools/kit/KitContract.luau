--!strict
-- Kit check: does one kit file follow the kit format of tools/world/README.md, so the
-- world-builder can place its templates? General for every game: it knows no tag or attribute
-- name. All names come in as `rules` (a game's Config.WorldRules, or test rules in the spec).
-- It works on an Instance tree from @lune/roblox and returns a list of problems; every problem
-- names the path of the object.
--
-- Why it exists: the asset-builder writes kits and the world-builder reads them. This check is
-- the contract between the two, so a kit that would break zone building fails in CI instead of
-- when the first zone is built.

local KitContract = {}

export type Rules = {
	ZoneNumberAttribute: string,
	StartTag: string,
	TagKinds: { [string]: string },
	GroupStreamingMode: string,
	PositiveAttributes: { { Tag: string, Attribute: string } },
}

-- Asset IDs a human uploaded, from tools/kit/<kit>/upload-list.json. Only these may appear.
export type Uploads = { meshIds: { [number]: boolean }, textureIds: { [number]: boolean } }

-- Rotation error tolerated on the PrimaryPart before it counts as turned.
local AXIS_TOLERANCE = 1e-4

local function pathOf(instance: any, root: any): string
	local names = {}
	local current = instance
	while current and current ~= root.Parent do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end
	return table.concat(names, ".")
end

local function isPositiveFinite(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- The asset URI of a MeshPart property. Files store it as MeshContent/TextureContent; an
-- instance built in memory only has MeshId/TextureID until it is written. Lune cannot read
-- MeshId/TextureID when they were never set, hence the pcall.
local function assetUri(item: any, contentName: string, idName: string): string?
	local ok, content = pcall(function()
		return item[contentName]
	end)
	if ok and content ~= nil and content.SourceType.Name ~= "None" then
		local uri = content.Uri
		if type(uri) == "string" and uri ~= "" then
			return uri
		end
	end
	local idOk, id = pcall(function()
		return item[idName]
	end)
	if idOk and type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

-- The numeric asset id in "rbxassetid://<n>", nil when there is none, false for anything else
-- (an http URL, rbxasset://, a local file): only uploaded ids are allowed.
local function assetNumber(uri: string?): number | false | nil
	if uri == nil then
		return nil
	end
	local digits = string.match(uri, "^rbxassetid://(%d+)$")
	return if digits then tonumber(digits) :: number else false
end

local function isAxisAligned(cframe: any): boolean
	local _, _, _, r00, _, _, _, r11, _, _, _, r22 = cframe:GetComponents()
	return math.abs(r00 - 1) < AXIS_TOLERANCE
		and math.abs(r11 - 1) < AXIS_TOLERANCE
		and math.abs(r22 - 1) < AXIS_TOLERANCE
end

-- Reads tools/kit/<kit>/upload-list.json contents (already decoded) into id sets.
-- Format: { "<mesh name>": { "meshId": <number>, "textureId": <number or null> } }.
function KitContract.uploadsFrom(list: any): (Uploads?, string?)
	if type(list) ~= "table" then
		return nil, "upload list must be an object"
	end
	local uploads: Uploads = { meshIds = {}, textureIds = {} }
	for name, entry in list do
		if type(name) ~= "string" or type(entry) ~= "table" then
			return nil, `upload list entry {tostring(name)} must be an object`
		end
		if not (type(entry.meshId) == "number" and entry.meshId > 0 and entry.meshId % 1 == 0) then
			return nil, `upload list entry {name} needs a whole positive meshId`
		end
		uploads.meshIds[entry.meshId] = true
		if entry.textureId ~= nil then
			if not (type(entry.textureId) == "number" and entry.textureId > 0 and entry.textureId % 1 == 0) then
				return nil, `upload list entry {name} has a textureId that is not a whole positive number`
			end
			uploads.textureIds[entry.textureId] = true
		end
	end
	return uploads, nil
end

-- All problems of one kit root (the single Folder in world/kits/<kit>.rbxmx).
function KitContract.check(root: any, rules: Rules, uploads: Uploads): { string }
	local problems: { string } = {}
	local function problem(instance: any, text: string)
		table.insert(problems, `{pathOf(instance, root)}: {text}`)
	end

	-- Attributes that stay the same when the world-builder scales a template.
	local sizeAttributes: { [string]: { [string]: boolean } } = {}
	for _, entry in rules.PositiveAttributes do
		sizeAttributes[entry.Tag] = sizeAttributes[entry.Tag] or {}
		sizeAttributes[entry.Tag][entry.Attribute] = true
	end

	if not root:IsA("Folder") then
		problem(root, `kit root must be a Folder, is {root.ClassName}`)
		return problems
	end

	local names: { [string]: boolean } = {}
	local templates = 0
	for _, template in root:GetChildren() do
		-- 1. Every child is a template Model with a unique name.
		if not template:IsA("Model") then
			problem(template, `only template Models belong in the kit folder, is {template.ClassName}`)
			continue
		end
		templates += 1
		if names[template.Name] then
			problem(template, "two templates share this name")
		end
		names[template.Name] = true

		-- 2. The PrimaryPart is the foot: a part inside the template, not turned, so the
		-- world-builder can stand the object on its underside.
		local primary = template.PrimaryPart
		if not primary or not primary:IsDescendantOf(template) then
			problem(template, "needs a PrimaryPart inside the template")
		elseif not isAxisAligned(primary.CFrame) then
			problem(primary, "PrimaryPart must not be rotated (the world-builder stands it on its underside)")
		end

		-- 3. Scale range: positive numbers, min not above max.
		local scaleMin = template:GetAttribute("ScaleMin")
		local scaleMax = template:GetAttribute("ScaleMax")
		if scaleMin ~= nil and not isPositiveFinite(scaleMin) then
			problem(template, `ScaleMin must be a positive number, is {scaleMin}`)
		end
		if scaleMax ~= nil and not isPositiveFinite(scaleMax) then
			problem(template, `ScaleMax must be a positive number, is {scaleMax}`)
		end
		local low = if isPositiveFinite(scaleMin) then scaleMin else 1
		local high = if isPositiveFinite(scaleMax) then scaleMax else 1
		if low > high then
			problem(template, `ScaleMin {low} is above ScaleMax {high}`)
		end
		local scalable = low ~= 1 or high ~= 1

		local function checkTagged(instance: any)
			if instance:GetAttribute(rules.ZoneNumberAttribute) ~= nil then
				problem(instance, `{rules.ZoneNumberAttribute} belongs on the zone root, not in a kit`)
			end
			for _, tag in instance:GetTags() do
				if tag == rules.StartTag then
					problem(instance, `{tag} is placed by the world-builder, not by the kit`)
				end
				local kind = rules.TagKinds[tag]
				if kind == "Point" and not (instance:IsA("Attachment") or instance:IsA("BasePart")) then
					problem(instance, `{tag} must be an Attachment or BasePart, is {instance.ClassName}`)
				elseif kind == "Part" and not instance:IsA("BasePart") then
					problem(instance, `{tag} must be a BasePart, is {instance.ClassName}`)
				elseif kind == "Group" then
					if not instance:IsA("Model") then
						problem(instance, `{tag} must be a Model, is {instance.ClassName}`)
					else
						local groupPrimary = instance.PrimaryPart
						if not groupPrimary or not groupPrimary:IsDescendantOf(instance) then
							problem(instance, `{tag} needs a PrimaryPart inside the Model`)
						end
						if instance.ModelStreamingMode.Name ~= rules.GroupStreamingMode then
							problem(instance, `{tag} needs ModelStreamingMode {rules.GroupStreamingMode}`)
						end
					end
				end
				if instance:IsA("MeshPart") and kind ~= nil then
					problem(instance, `{tag} belongs on an invisible part or the Model, not on the mesh`)
				end
				-- 4. Positive attributes; the world-builder scales sizes but not attributes, so a
				-- template that carries one cannot be scalable.
				for attribute in sizeAttributes[tag] or {} do
					local value = instance:GetAttribute(attribute)
					if value ~= nil then
						if not isPositiveFinite(value) then
							problem(instance, `{attribute} must be a positive number, is {value}`)
						end
						if scalable then
							problem(
								template,
								`carries {attribute}, which does not scale; make one template per size with ScaleMin = ScaleMax = 1`
							)
						end
					end
				end
			end
		end

		checkTagged(template)
		for _, item in template:GetDescendants() do
			checkTagged(item)
			-- 5. No code and no mesh kinds the world-builder cannot scale.
			if item:IsA("LuaSourceContainer") then
				problem(item, `kits hold no scripts ({item.ClassName})`)
			elseif item:IsA("DataModelMesh") then
				problem(item, `{item.ClassName} does not scale with the template; use a MeshPart`)
			elseif item:IsA("MeshPart") then
				-- 6. The mesh is only the look.
				if item.CanCollide or item.CanQuery or item.CanTouch then
					problem(item, "mesh must have CanCollide, CanQuery and CanTouch off")
				end
				if not item.Anchored then
					problem(item, "mesh must be Anchored")
				end
				-- 7. Asset ids only from the upload list.
				local meshUri = assetUri(item, "MeshContent", "MeshId")
				local mesh = assetNumber(meshUri)
				if mesh == nil then
					problem(item, "mesh has no MeshId (waiting for upload: leave it out of the kit)")
				elseif mesh == false or not uploads.meshIds[mesh] then
					problem(item, `MeshId {meshUri} is not in the upload list`)
				end
				local textureUri = assetUri(item, "TextureContent", "TextureID")
				local texture = assetNumber(textureUri)
				if texture == false or (texture ~= nil and not uploads.textureIds[texture]) then
					problem(item, `TextureID {textureUri} is not in the upload list`)
				end
			elseif item:IsA("BasePart") then
				-- Collision and contact parts: invisible and anchored.
				if item.Transparency ~= 1 or not item.Anchored then
					problem(item, "non-mesh parts are collision or contact parts: Transparency 1 and Anchored")
				end
			end
		end
	end

	if templates == 0 then
		problem(root, "kit has no templates")
	end

	table.sort(problems)
	return problems
end

return table.freeze(KitContract)

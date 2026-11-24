--!strict
-- Zone check: does one zone file follow the world rules? General for every game: it knows no
-- tag or attribute name. All names come in as `rules` (a game's Config.WorldRules, or test
-- rules in the spec). It works on an Instance tree from @lune/roblox and returns a list of
-- problems; every problem names the path of the object, so a builder can find it.

local ZoneContract = {}

export type Range = { Min: number?, Max: number? }
export type Share = { Tag: string, Attribute: string, Min: number?, Max: number? }
export type Limits = { Counts: { [string]: Range }?, Shares: { Share }? }
export type Rules = {
	ZoneFilePattern: string,
	ZoneNumberAttribute: string,
	MaxZoneNumber: number,
	BoundsFolder: string,
	StartTag: string,
	TagKinds: { [string]: string },
	GroupStreamingMode: string,
	PositiveAttributes: { { Tag: string, Attribute: string } },
	Counts: { [string]: Range },
	Shares: { Share },
	Worlds: { [string]: Limits },
}

local function pathOf(instance: any, root: any): string
	local names = {}
	local current = instance
	while current and current ~= root.Parent do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end
	return table.concat(names, ".")
end

local function isWhole(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0
end

local function isPositiveFinite(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- What counts as one object: the nearest Model above the tagged instance (an object made of
-- several parts counts once), else the instance itself.
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

local function checkRange(problems: { string }, label: string, value: number, range: Range)
	if range.Min and value < range.Min then
		table.insert(problems, `{label}: {value}, needs at least {range.Min}`)
	end
	if range.Max and value > range.Max then
		table.insert(problems, `{label}: {value}, allows at most {range.Max}`)
	end
end

-- The limits for one world folder: the world's own, else the ones for every world.
function ZoneContract.limitsFor(rules: Rules, worldName: string): Limits
	local world = rules.Worlds[worldName]
	return {
		Counts = (world and world.Counts) or rules.Counts,
		Shares = (world and world.Shares) or rules.Shares,
	}
end

-- The zone number in a file name, or nil when the file is not a zone file.
function ZoneContract.fileZone(rules: Rules, fileName: string): number?
	local digits = string.match(fileName, rules.ZoneFilePattern)
	return if digits then tonumber(digits) else nil
end

-- All problems of one zone root. `fileZone` is the number from the file name; nil skips the
-- name check.
function ZoneContract.check(root: any, fileZone: number?, rules: Rules, limits: Limits): { string }
	local problems: { string } = {}
	local function problem(instance: any, text: string)
		table.insert(problems, `{pathOf(instance, root)}: {text}`)
	end
	local numberName = rules.ZoneNumberAttribute

	-- 1. The zone root: a Folder, or a Model that streams like a Folder, with its zone number.
	if root:IsA("Model") then
		local mode = root.ModelStreamingMode.Name
		if mode == "Atomic" or mode == "Persistent" then
			problem(root, `zone root must not use ModelStreamingMode {mode}`)
		end
	elseif not root:IsA("Folder") then
		problem(root, `zone root must be a Folder or Model, is {root.ClassName}`)
	end
	local number = root:GetAttribute(numberName)
	if not (isWhole(number) and number >= 1 and number <= rules.MaxZoneNumber) then
		problem(root, `{numberName} must be a whole number 1-{rules.MaxZoneNumber}, is {number}`)
	elseif fileZone and number ~= fileZone then
		problem(root, `{numberName} {number} does not match the file name (Zone{string.format("%02d", fileZone)})`)
	end

	-- Collect every tag once.
	local tagged: { [string]: { any } } = {}
	for _, instance in root:GetDescendants() do
		if instance:GetAttribute(numberName) ~= nil then
			problem(instance, `{numberName} only belongs on the zone root`)
		end
		for _, tag in instance:GetTags() do
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], instance)
		end
	end

	-- 2. Exactly one zone start.
	local starts = tagged[rules.StartTag] or {}
	if #starts ~= 1 then
		problem(root, `needs exactly 1 {rules.StartTag}, has {#starts}`)
	end

	-- 3. Every tag sits on the kind of object the rules ask for.
	for tag, kind in rules.TagKinds do
		for _, instance in tagged[tag] or {} do
			if kind == "Point" then
				if not (instance:IsA("Attachment") or instance:IsA("BasePart")) then
					problem(instance, `{tag} must be an Attachment or BasePart, is {instance.ClassName}`)
				end
			elseif kind == "Part" then
				if not instance:IsA("BasePart") then
					problem(instance, `{tag} must be a BasePart, is {instance.ClassName}`)
				end
			elseif kind == "Group" then
				if not instance:IsA("Model") then
					problem(instance, `{tag} must be a Model, is {instance.ClassName}`)
					continue
				end
				local primary = instance.PrimaryPart
				if not primary or not primary:IsDescendantOf(instance) then
					problem(instance, `{tag} needs a PrimaryPart inside the Model`)
				end
				if instance.ModelStreamingMode.Name ~= rules.GroupStreamingMode then
					problem(instance, `{tag} needs ModelStreamingMode {rules.GroupStreamingMode}`)
				end
			end
		end
	end

	-- 4. Attributes that must be positive numbers when set.
	for _, entry in rules.PositiveAttributes do
		for _, instance in tagged[entry.Tag] or {} do
			local value = instance:GetAttribute(entry.Attribute)
			if value ~= nil and not isPositiveFinite(value) then
				problem(instance, `{entry.Attribute} must be a positive number, is {value}`)
			end
		end
	end

	-- 5. Invisible walls at the zone edge: anchored, colliding, invisible parts.
	local bounds = root:FindFirstChild(rules.BoundsFolder)
	if not bounds then
		problem(root, `needs a {rules.BoundsFolder} folder with the invisible walls`)
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

	-- 6. Optional counts per tag, counted per object.
	for tag, range in limits.Counts or {} do
		local seen: { [any]: boolean } = {}
		local count = 0
		for _, instance in tagged[tag] or {} do
			local object = objectOf(instance, root)
			if not seen[object] then
				seen[object] = true
				count += 1
			end
		end
		checkRange(problems, `{root.Name}: {tag} objects`, count, range)
	end

	-- 7. Optional shares: how many <tag> objects carry a positive <attribute>.
	for _, share in limits.Shares or {} do
		local objects: { [any]: boolean } = {}
		local total, with = 0, 0
		for _, instance in tagged[share.Tag] or {} do
			local object = objectOf(instance, root)
			local has = isPositiveFinite(instance:GetAttribute(share.Attribute))
			if objects[object] == nil then
				objects[object] = has
				total += 1
				if has then
					with += 1
				end
			elseif has and not objects[object] then
				objects[object] = true
				with += 1
			end
		end
		if total > 0 then
			checkRange(problems, `{root.Name}: share of {share.Tag} with {share.Attribute}`, with / total, share)
		end
	end

	table.sort(problems)
	return problems
end

-- Problems across all zones of one world: the same zone number used twice.
function ZoneContract.checkWorld(roots: { any }, rules: Rules): { string }
	local problems: { string } = {}
	local seen: { [number]: string } = {}
	for _, root in roots do
		local number = root:GetAttribute(rules.ZoneNumberAttribute)
		if isWhole(number) then
			if seen[number] then
				table.insert(problems, `{rules.ZoneNumberAttribute} {number} used by {seen[number]} and {root.Name}`)
			else
				seen[number] = root.Name
			end
		end
	end
	return problems
end

return table.freeze(ZoneContract)

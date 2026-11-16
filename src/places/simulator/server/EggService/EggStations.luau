--!strict
-- Egg stations on the map (concept 7.9, ADR 0009, ADR 0013). Binds every `EggStation` station
-- below Workspace.Map that the station rules accept and whose zone has an egg
-- (Config.Pets.EggZones): a ProximityPrompt (Prompts preset "EggStation") on its PrimaryPart with
-- the egg number and whether it is on sale. The prompt changes no state; the client sends
-- EggHatch, and the server finds the station again with eggNear().
--
-- Invalid stations warn once per instance and are not bound. Nothing throws.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Prompts = require(Shared:WaitForChild("Prompts"))

-- The ADR 0009 station checks of the upgrade stand (#36). Used as is, not moved: a shared map
-- resolver is open for the station features (#38-#41) to agree on (ADR 0013 open question).
local StationRules = require(script.Parent.Parent:WaitForChild("UpgradeService"):WaitForChild("StationRules"))

export type Options = {
	map: any, -- Config.Map
	studioTest: any, -- Config.Eggs.StudioTest
	worldIndex: number,
	zoneCount: number,
	isZone: (value: any) -> boolean,
	worldOf: (zone: number) -> number,
	eggForZone: (zone: number) -> number?,
	isAvailable: (egg: number) -> boolean,
	-- Prompt distance + Config.Eggs.StationReachTolerance.
	reach: number,
	log: (message: string) -> (),
}

export type Stations = {
	count: () -> number,
	-- The egg of the closest bound station within reach of `position`, or nil.
	eggNear: (position: Vector3) -> number?,
	-- Studio only (EggStationTestGeometry): builds Workspace.Map.<AreaName> with one station in
	-- front of `origin`, or removes it. Returns a log line.
	setTestGeometry: (enabled: boolean, origin: CFrame?) -> string,
}

type Bound = { prompt: ProximityPrompt, primary: BasePart, egg: number }

local EggStations = {}

function EggStations.start(options: Options): Stations
	local mapConfig = options.map
	local tag = mapConfig.Tags.EggStation
	local stationConfig = mapConfig.EggStation

	local function mapFolder(): Instance?
		return Workspace:FindFirstChild(mapConfig.FolderName)
	end

	local rules = StationRules.new({
		worldIndex = options.worldIndex,
		zoneCount = options.zoneCount,
		isZone = options.isZone,
		worldOf = options.worldOf,
		stationStreamingMode = mapConfig.StationStreamingMode,
		zoneIndexAttribute = mapConfig.ZoneIndexAttribute,
	}, {
		parent = function(node: any): any
			return node.Parent
		end,
		isMapRoot = function(node: any): boolean
			return node.Parent == Workspace and node.Name == mapConfig.FolderName
		end,
		mapChildren = function(): { any }
			local folder = mapFolder()
			return if folder then folder:GetChildren() else {}
		end,
		isModel = function(node: any): boolean
			return node:IsA("Model")
		end,
		primaryPart = function(node: any): any
			return node.PrimaryPart
		end,
		streamingMode = function(node: any): string
			return node.ModelStreamingMode.Name
		end,
		zoneIndex = function(node: any): any
			return node:GetAttribute(mapConfig.ZoneIndexAttribute)
		end,
		name = function(node: any): string
			return node.Name
		end,
	})

	local bound: { [Instance]: Bound } = {}
	local warned: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local boundCount = 0

	local function warnOnce(instance: Instance, problem: string)
		if not warned[instance] then
			warned[instance] = true
			warn(StationRules.warning(tag, instance:GetFullName(), problem))
		end
	end

	local function bind(instance: Instance)
		if bound[instance] then
			return
		end
		local verdict = rules.checkStation(instance)
		if verdict.status == "OutOfScope" then
			return
		end
		if verdict.status == "Invalid" then
			warnOnce(instance, verdict.problem or "invalid")
			return
		end
		local zone = verdict.zone :: number
		local egg = options.eggForZone(zone)
		if egg == nil then
			warnOnce(instance, `zone {zone} has no egg (Config.Pets.EggZones)`)
			return
		end
		local primary = (instance :: Model).PrimaryPart :: BasePart
		local open = options.isAvailable(egg)
		local prompt = Prompts.create("EggStation", primary, {
			name = stationConfig.PromptName,
			tag = stationConfig.PromptTag,
		})
		prompt:SetAttribute(stationConfig.EggAttribute, egg)
		prompt:SetAttribute(stationConfig.OpenAttribute, open)
		-- A closed station keeps its label ("Coming soon") but offers nothing (ADR 0009).
		prompt.Enabled = open
		bound[instance] = { prompt = prompt, primary = primary, egg = egg }
		boundCount += 1
		options.log(`station bound {instance:GetFullName()} zone={zone} egg={egg} open={open}`)
	end

	local function unbind(instance: Instance)
		local entry = bound[instance]
		if entry == nil then
			return
		end
		bound[instance] = nil
		boundCount -= 1
		entry.prompt:Destroy()
		options.log(`station unbound {instance:GetFullName()}`)
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbind)
	for _, instance in CollectionService:GetTagged(tag) do
		bind(instance)
	end

	local function eggNear(position: Vector3): number?
		local best: number? = nil
		local bestDistance = options.reach
		for _, entry in bound do
			if entry.primary.Parent ~= nil then
				local distance = (entry.primary.Position - position).Magnitude
				if distance <= bestDistance then
					best = entry.egg
					bestDistance = distance
				end
			end
		end
		return best
	end

	local function part(name: string, size: { number }, at: CFrame): Part
		local created = Instance.new("Part")
		created.Name = name
		created.Anchored = true
		created.Size = Vector3.new(size[1], size[2], size[3])
		created.CFrame = at
		return created
	end

	local function setTestGeometry(enabled: boolean, origin: CFrame?): string
		local test = options.studioTest
		local folder = mapFolder()
		if folder == nil then
			return `no Workspace.{mapConfig.FolderName}`
		end
		local old = folder:FindFirstChild(test.AreaName)
		if old then
			old:Destroy()
		end
		if not enabled then
			return "test egg station removed"
		end
		if origin == nil then
			return "no character to place the test egg station at"
		end
		-- Another area with the same ZoneIndex would make both zone-less (ADR 0009), and the
		-- station would warn instead of binding. Refuse instead of breaking the other area.
		for _, child in folder:GetChildren() do
			if child:GetAttribute(mapConfig.ZoneIndexAttribute) == test.ZoneIndex then
				return `ZoneIndex {test.ZoneIndex} is already used by {child:GetFullName()}; remove that area first`
			end
		end

		local front = origin * CFrame.new(0, 0, -test.Distance)
		local groundY = origin.Position.Y - 3
		local base = CFrame.new(front.Position.X, groundY + test.BaseSize[2] / 2, front.Position.Z)
		local model = Instance.new("Model")
		model.Name = "EggStation"
		model.ModelStreamingMode = (Enum.ModelStreamingMode :: any)[mapConfig.StationStreamingMode]
		local basePart = part("Base", test.BaseSize, base)
		basePart.Parent = model
		local egg = part("Egg", test.EggSize, base * CFrame.new(0, (test.BaseSize[2] + test.EggSize[2]) / 2, 0))
		-- A sphere mesh stretched to the part's size reads as an egg; a Ball part would be round.
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = egg
		egg.Parent = model
		local anchor = Instance.new("Attachment")
		anchor.Name = mapConfig.LabelAnchorName
		anchor.Position = Vector3.new(0, test.LabelHeight, 0)
		anchor.Parent = basePart
		model.PrimaryPart = basePart
		CollectionService:AddTag(model, tag)

		-- Built unparented and parented last, so the tag check sees the whole tree at once.
		local area = Instance.new("Folder")
		area.Name = test.AreaName
		area:SetAttribute(mapConfig.ZoneIndexAttribute, test.ZoneIndex)
		model.Parent = area
		area.Parent = folder
		return `test egg station built in {area:GetFullName()} (ZoneIndex {test.ZoneIndex})`
	end

	return table.freeze({
		count = function(): number
			return boundCount
		end,
		eggNear = eggNear,
		setTestGeometry = setTestGeometry,
	})
end

return table.freeze(EggStations)

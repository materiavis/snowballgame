--!strict
-- Scale plates on the map (concept 7.5, ADR 0009, ADR 0012). Binds every `ScalePlate` BasePart
-- below Workspace.Map whose zone area has a valid ZoneIndex, and measures the gap between a
-- ball and the nearest bound plate. Zone rules come from StationRules (ADR 0009 "Zone number").
--
-- Invalid plates warn once per instance and are not bound; templates outside Workspace.Map are
-- ignored silently; a zone area without any plate warns once per zone. Nothing throws.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlateGeometry = require(script.Parent:WaitForChild("PlateGeometry"))
local StationRules = require(script.Parent.Parent:WaitForChild("UpgradeService"):WaitForChild("StationRules"))

export type Options = {
	map: any, -- Config.Map
	sell: any, -- Config.Sell
	scaleAnchorTag: string, -- Config.Ball.ScaleAnchorTag
	worldIndex: number,
	zoneCount: number,
	isZone: (value: any) -> boolean,
	worldOf: (zone: number) -> number,
	log: (message: string) -> (),
}

export type Plates = {
	count: () -> number,
	-- Smallest gap from a ball (centre, radius) to a bound plate, and that plate's zone.
	-- math.huge and nil without plates.
	nearest: (position: Vector3, radius: number) -> (number, number?),
	-- Studio only (SellScaleTestGeometry): builds the test scale in a zone area with ZoneIndex
	-- `zone` in front of `origin`, or removes it for zone 0. Returns a log line.
	setTestGeometry: (zone: number, origin: CFrame?, exclude: { Instance }) -> string,
}

local ScalePlates = {}

function ScalePlates.start(options: Options): Plates
	local mapConfig = options.map
	local test = options.sell.Test
	local tag = mapConfig.Tags.ScalePlate
	local zoneAttribute = mapConfig.ZoneIndexAttribute

	local function mapFolder(): Instance?
		return Workspace:FindFirstChild(mapConfig.FolderName)
	end

	local rules = StationRules.new({
		worldIndex = options.worldIndex,
		zoneCount = options.zoneCount,
		isZone = options.isZone,
		worldOf = options.worldOf,
		stationStreamingMode = mapConfig.StationStreamingMode,
		zoneIndexAttribute = zoneAttribute,
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
			return node:GetAttribute(zoneAttribute)
		end,
		name = function(node: any): string
			return node.Name
		end,
	})

	local plates: { [BasePart]: number } = {}
	local warned: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local warnedZones: { [number]: boolean } = {}
	local bound = 0

	local function warnOnce(instance: Instance, problem: string)
		if not warned[instance] then
			warned[instance] = true
			warn(StationRules.warning(tag, instance:GetFullName(), problem))
		end
	end

	-- A zone area without a plate has no selling: one warning per zone (ADR 0009).
	local function checkZones()
		local folder = mapFolder()
		if folder == nil then
			return
		end
		local withPlate: { [number]: boolean } = {}
		for _, zone in plates do
			withPlate[zone] = true
		end
		for _, area in folder:GetChildren() do
			local zone = rules.zoneOf(area)
			if zone ~= nil and not withPlate[zone] and not warnedZones[zone] then
				warnedZones[zone] = true
				warn(`[MapContract] {tag} {area:GetFullName()}: zone {zone} has no {tag}, so it has no selling`)
			end
		end
	end

	local checkQueued = false
	local function queueCheck()
		if checkQueued then
			return
		end
		checkQueued = true
		-- Deferred, so the plates of an area that arrives as a whole are bound first.
		task.defer(function()
			checkQueued = false
			checkZones()
		end)
	end

	local function bind(instance: Instance)
		if not instance:IsA("BasePart") then
			if rules.areaOf(instance) ~= nil then
				warnOnce(instance, "a ScalePlate must be a BasePart")
			end
			return
		end
		if plates[instance] ~= nil then
			return
		end
		if rules.areaOf(instance) == nil then
			return
		end
		local zone, problem = rules.zoneOf(instance)
		if zone == nil then
			warnOnce(instance, `not in a zone: {problem or "no zone"}`)
			return
		end
		plates[instance] = zone
		bound += 1
		options.log(`plate bound {instance:GetFullName()} zone={zone}`)
		queueCheck()
	end

	local function unbind(instance: Instance)
		if instance:IsA("BasePart") and plates[instance] ~= nil then
			plates[instance] = nil
			bound -= 1
			options.log(`plate unbound {instance:GetFullName()}`)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbind)
	for _, instance in CollectionService:GetTagged(tag) do
		bind(instance)
	end
	local folder = mapFolder()
	if folder then
		folder.ChildAdded:Connect(queueCheck)
	end
	queueCheck()

	local function nearest(position: Vector3, radius: number): (number, number?)
		local best, bestZone = math.huge, nil
		for plate, zone in plates do
			if plate:IsDescendantOf(Workspace) then
				local localPoint = plate.CFrame:PointToObjectSpace(position)
				local half = plate.Size / 2
				local distance =
					PlateGeometry.boxDistance(localPoint.X, localPoint.Y, localPoint.Z, half.X, half.Y, half.Z)
				local gap = PlateGeometry.gap(distance, radius)
				if gap < best then
					best, bestZone = gap, zone
				end
			end
		end
		return best, bestZone
	end

	local function removeTest()
		local map = mapFolder()
		local old = map and map:FindFirstChild(test.AreaName)
		if old then
			old:Destroy()
		end
		local decoy = ServerStorage:FindFirstChild(test.DecoyName)
		if decoy then
			decoy:Destroy()
		end
	end

	local function zoneProblem(map: Instance, zone: number): string?
		if not options.isZone(zone) or options.worldOf(zone) ~= options.worldIndex then
			return `{zone} is not a zone of world {options.worldIndex}`
		end
		for _, child in map:GetChildren() do
			if child:GetAttribute(zoneAttribute) == zone then
				return `{child:GetFullName()} already has {zoneAttribute} {zone}`
			end
		end
		return nil
	end

	local function groundBelow(at: Vector3, exclude: { Instance }): number?
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclude
		local origin = at + Vector3.new(0, test.GroundSearchHeight, 0)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -test.GroundSearchDepth, 0), params)
		return if hit then hit.Position.Y else nil
	end

	local function setTestGeometry(zone: number, origin: CFrame?, exclude: { Instance }): string
		removeTest()
		if zone == 0 then
			return "test scale removed"
		end
		local map = mapFolder()
		if map == nil then
			return `no Workspace.{mapConfig.FolderName}`
		end
		local problem = zoneProblem(map, zone)
		if problem then
			return `not built: {problem}`
		end
		if origin == nil then
			return "not built: no character to place the test scale at"
		end
		-- Level with the character's facing, so the plate lies flat on flat ground.
		local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
		if look.Magnitude < 1e-3 then
			look = Vector3.new(0, 0, -1)
		end
		local centre = origin.Position + look.Unit * test.Distance
		local groundY = groundBelow(centre, exclude)
		if groundY == nil then
			return "not built: no ground in front of the character"
		end
		local size = Vector3.new(test.PlateSize[1], test.PlateSize[2], test.PlateSize[3])
		local top = groundY + test.PlateRaise
		local at = CFrame.lookAt(
			Vector3.new(centre.X, top - size.Y / 2, centre.Z),
			Vector3.new(centre.X, top - size.Y / 2, centre.Z) + look
		)

		-- Built unparented and parented last, so the tag binding sees the whole area at once.
		local area = Instance.new("Folder")
		area.Name = test.AreaName
		area:SetAttribute(zoneAttribute, zone)
		local plate = Instance.new("Part")
		plate.Name = "ScalePlate"
		plate.Anchored = true
		plate.Size = size
		plate.CFrame = at
		plate.Color = Color3.fromRGB(test.PlateColorRGB[1], test.PlateColorRGB[2], test.PlateColorRGB[3])
		plate.Material = Enum.Material.SmoothPlastic
		plate.TopSurface = Enum.SurfaceType.Smooth
		CollectionService:AddTag(plate, tag)
		local anchor = Instance.new("Attachment")
		anchor.Name = "ScaleAnchor"
		anchor.Position = Vector3.new(0, size.Y / 2 + test.AnchorHeight, 0)
		anchor.Parent = plate
		CollectionService:AddTag(anchor, options.scaleAnchorTag)
		plate.Parent = area

		-- A tagged ScaleAnchor template outside Workspace.Map, nearer than the real one: the
		-- MAX arrow must ignore it (ADR 0009 "Scope").
		local decoy = Instance.new("Part")
		decoy.Name = test.DecoyName
		decoy.Anchored = true
		decoy.CFrame = origin
		CollectionService:AddTag(decoy, options.scaleAnchorTag)
		decoy.Parent = ServerStorage

		area.Parent = map
		return `test scale built in {area:GetFullName()} ({zoneAttribute} {zone}), plate top at y={string.format(
			"%.2f",
			top
		)}, decoy ScaleAnchor in {decoy:GetFullName()}`
	end

	return table.freeze({
		count = function(): number
			return bound
		end,
		nearest = nearest,
		setTestGeometry = setTestGeometry,
	})
end

return table.freeze(ScalePlates)

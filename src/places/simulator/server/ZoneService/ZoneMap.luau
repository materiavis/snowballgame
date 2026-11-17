--!strict
-- Reads Workspace.Map for ZoneService (ADR 0009, ADR 0014): zone areas, ZoneStart anchors and
-- Barrier stations. Roblox-facing; the rules are StationRules (ZoneIndex, Station rule) and
-- ZoneAreas (starts, boxes, position lookup).
--
-- The map is read again (deferred, once per frame at most) when a direct child of Workspace.Map
-- is added or removed, a ZoneIndex changes, or a ZoneStart or Barrier tag appears or goes.
-- Problems warn once per instance and text (`[MapContract] <tag> <full name>: <problem>,
-- ignored`) and never throw. Every bound barrier gets the server-written attributes
-- BarrierZone and BarrierCanOpen, the client contract for labels, prompts and passability.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local StationRules = require(script.Parent.Parent:WaitForChild("UpgradeService"):WaitForChild("StationRules"))
local ZoneAreas = require(script.Parent:WaitForChild("ZoneAreas"))

export type Options = {
	map: any, -- Config.Map
	worldIndex: number,
	zoneCount: number,
	isZone: (value: any) -> boolean,
	worldOf: (zone: number) -> number,
	isWorldGate: (zone: number) -> boolean,
	-- ZoneCore.barrierState: can the barrier at the end of this zone open here?
	barrierState: (zone: number) -> (boolean, string?),
	diagnostics: boolean,
	log: (message: string) -> (),
}

export type ZoneMap = {
	hasZone: (zone: number) -> boolean,
	hasBarrier: (zone: number) -> boolean,
	-- Where a character stands at the start of `zone`, or nil without a start.
	startCFrame: (zone: number) -> CFrame?,
	zoneAt: (position: Vector3, preferred: number?) -> number?,
	-- The zone area an instance belongs to (ADR 0009 "Resolve"), or nil.
	zoneOf: (instance: Instance) -> number?,
	zones: () -> { number },
	describe: () -> string,
	onChanged: (listener: () -> ()) -> (),
	refreshNow: () -> (),
}

local ZoneMap = {}

local function anchorCFrame(anchor: Instance): CFrame?
	if anchor:IsA("Attachment") then
		return anchor.WorldCFrame
	elseif anchor:IsA("BasePart") then
		-- On top of a pad, not inside it.
		return anchor.CFrame + Vector3.new(0, anchor.Size.Y / 2, 0)
	end
	return nil
end

local function partBox(part: BasePart): ZoneAreas.Box
	local cf = part.CFrame
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local size = part.Size
	return ZoneAreas.partBox(
		{ cf.X, cf.Y, cf.Z },
		{ r00, r01, r02, r10, r11, r12, r20, r21, r22 },
		{ size.X, size.Y, size.Z }
	)
end

local function areaBox(area: Instance): ZoneAreas.Box?
	local boxes: { ZoneAreas.Box } = {}
	if area:IsA("BasePart") then
		table.insert(boxes, partBox(area))
	end
	for _, descendant in area:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(boxes, partBox(descendant))
		end
	end
	return ZoneAreas.union(boxes)
end

function ZoneMap.start(options: Options): ZoneMap
	local mapConfig = options.map
	local tags = mapConfig.Tags
	local barrierConfig = mapConfig.Barrier
	local areaConfig = mapConfig.ZoneAreas
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

	local warned: { [Instance]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
	local function warnOnce(instance: Instance, tag: string, problem: string)
		local seen = warned[instance]
		if seen == nil then
			seen = {}
			warned[instance] = seen
		end
		if not seen[problem] then
			seen[problem] = true
			warn(StationRules.warning(tag, instance:GetFullName(), problem))
		end
	end

	local snapshot = ZoneAreas.snapshot({}, { verticalMargin = areaConfig.VerticalMargin, startTag = tags.ZoneStart })
	local starts: { [number]: Instance } = {}
	local barriers: { [number]: { Model } } = {}
	local bound: { [Model]: number } = {}
	local listeners: { () -> () } = {}

	local function clearBarrier(model: Instance)
		model:SetAttribute(barrierConfig.ZoneAttribute, nil)
		model:SetAttribute(barrierConfig.CanOpenAttribute, nil)
		model:SetAttribute(barrierConfig.ClosedReasonAttribute, nil)
	end

	local function readAreas(folder: Instance): ({ ZoneAreas.AreaRecord }, { [Instance]: Instance })
		-- ZoneStart anchors per area root first.
		local startCount: { [Instance]: number } = {}
		local startOf: { [Instance]: Instance } = {}
		for _, anchor in CollectionService:GetTagged(tags.ZoneStart) do
			local area = rules.areaOf(anchor)
			if area == nil then
				continue -- outside Workspace.Map: a template, ignored silently
			end
			if not (anchor:IsA("Attachment") or anchor:IsA("BasePart")) then
				warnOnce(anchor, tags.ZoneStart, "must be an Attachment or a BasePart")
				continue
			end
			local zone, problem = rules.zoneOf(anchor)
			if zone == nil then
				warnOnce(anchor, tags.ZoneStart, `not in a zone: {problem or "no zone"}`)
				continue
			end
			startCount[area] = (startCount[area] or 0) + 1
			startOf[area] = anchor
		end

		local records: { ZoneAreas.AreaRecord } = {}
		for _, child in folder:GetChildren() do
			local zone, problem = rules.zoneOf(child)
			-- An area without ZoneIndex (the Placeholder) simply has no zone; only its zone-bound
			-- entries warn. An invalid or duplicate value warns here.
			if child:GetAttribute(zoneAttribute) == nil then
				problem = nil
			end
			table.insert(records, {
				key = child,
				name = child:GetFullName(),
				zone = zone,
				problem = problem,
				starts = startCount[child] or 0,
				box = if zone ~= nil then areaBox(child) else nil,
			})
		end
		return records, startOf
	end

	local function readBarriers(): { [Model]: number }
		local found: { [Model]: number } = {}
		for _, instance in CollectionService:GetTagged(tags.Barrier) do
			local verdict = rules.checkStation(instance)
			if verdict.status == "OutOfScope" then
				continue
			end
			if verdict.status == "Invalid" then
				warnOnce(instance, tags.Barrier, verdict.problem or "invalid")
				continue
			end
			local zone = verdict.zone :: number
			if options.isWorldGate(zone) or zone >= options.zoneCount then
				warnOnce(instance, tags.Barrier, `zone {zone} ends in a WorldGate, not a Barrier`)
				continue
			end
			found[instance :: Model] = zone
		end
		return found
	end

	local function refresh()
		local folder = mapFolder()
		local records, startOf = {}, {}
		if folder ~= nil then
			records, startOf = readAreas(folder)
		end
		snapshot =
			ZoneAreas.snapshot(records, { verticalMargin = areaConfig.VerticalMargin, startTag = tags.ZoneStart })
		for _, problem in snapshot.problems do
			warnOnce(problem.key, problem.tag, problem.text)
		end
		starts = {}
		for _, zone in snapshot.zones do
			local area = (snapshot.area(zone) :: ZoneAreas.AreaRecord).key
			if snapshot.hasZone(zone) then
				starts[zone] = startOf[area]
			end
		end

		local found = readBarriers()
		barriers = {}
		for model, zone in found do
			local list = barriers[zone] or {}
			table.insert(list, model)
			barriers[zone] = list
		end
		for _, zone in snapshot.zones do
			local area = (snapshot.area(zone) :: ZoneAreas.AreaRecord).key
			local count = if barriers[zone] then #barriers[zone] else 0
			if options.isWorldGate(zone) or zone >= options.zoneCount then
				continue
			end
			if count == 0 then
				warnOnce(area, tags.Barrier, `zone {zone} has no Barrier, so zone {zone + 1} is unreachable`)
			elseif count > 1 then
				warnOnce(area, tags.Barrier, `zone {zone} has {count} Barrier stations; all of them work`)
			end
		end

		for model in bound do
			if found[model] == nil then
				clearBarrier(model)
			end
		end
		for model, zone in found do
			local canOpen, reason = options.barrierState(zone)
			model:SetAttribute(barrierConfig.ZoneAttribute, zone)
			model:SetAttribute(barrierConfig.CanOpenAttribute, canOpen)
			if options.diagnostics then
				model:SetAttribute(barrierConfig.ClosedReasonAttribute, reason or "")
			end
			if bound[model] ~= zone then
				options.log(`barrier bound {model:GetFullName()} zone={zone} canOpen={canOpen} {reason or ""}`)
			end
		end
		bound = found

		for _, listener in table.clone(listeners) do
			task.spawn(listener)
		end
	end

	local scheduled = false
	local function schedule()
		if scheduled then
			return
		end
		scheduled = true
		task.defer(function()
			scheduled = false
			refresh()
		end)
	end

	local watched: { [Instance]: RBXScriptConnection } = {}
	local function watchChild(child: Instance)
		if watched[child] == nil then
			watched[child] = child:GetAttributeChangedSignal(zoneAttribute):Connect(schedule)
		end
	end
	local function watchFolder(folder: Instance)
		folder.ChildAdded:Connect(function(child: Instance)
			watchChild(child)
			schedule()
		end)
		folder.ChildRemoved:Connect(function(child: Instance)
			local connection = watched[child]
			if connection then
				connection:Disconnect()
				watched[child] = nil
			end
			schedule()
		end)
		for _, child in folder:GetChildren() do
			watchChild(child)
		end
	end

	local folder = mapFolder()
	if folder then
		watchFolder(folder)
	else
		Workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == mapConfig.FolderName and mapFolder() == child then
				watchFolder(child)
				schedule()
			end
		end)
	end
	for _, tag in { tags.ZoneStart, tags.Barrier } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(schedule)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(schedule)
	end
	-- No read here: barrierState reaches back into this map through ZoneCore, so the caller
	-- runs refreshNow() once it holds the returned table.

	local function startCFrame(zone: number): CFrame?
		local anchor = starts[zone]
		if anchor == nil or anchor.Parent == nil then
			return nil
		end
		local cf = anchorCFrame(anchor)
		if cf == nil then
			return nil
		end
		local position = cf.Position + Vector3.new(0, areaConfig.StartHeight, 0)
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if look.Magnitude < 1e-3 then
			return CFrame.new(position)
		end
		return CFrame.lookAt(position, position + look.Unit)
	end

	local function describe(): string
		local barrierText: { string } = {}
		for _, zone in snapshot.zones do
			if barriers[zone] then
				local canOpen, reason = options.barrierState(zone)
				local state = if canOpen then "open" else `closed({reason})`
				table.insert(barrierText, `{zone}:{state}`)
			end
		end
		local startText: { string } = {}
		for _, zone in snapshot.zones do
			if snapshot.hasZone(zone) then
				table.insert(startText, tostring(zone))
			end
		end
		local zoneText: { string } = {}
		for _, zone in snapshot.zones do
			table.insert(zoneText, tostring(zone))
		end
		return `zones={table.concat(zoneText, ",")} starts={table.concat(startText, ",")} barriers={table.concat(
			barrierText,
			","
		)}`
	end

	return table.freeze({
		hasZone = function(zone: number): boolean
			return snapshot.hasZone(zone)
		end,
		hasBarrier = function(zone: number): boolean
			return barriers[zone] ~= nil
		end,
		startCFrame = startCFrame,
		zoneAt = function(position: Vector3, preferred: number?): number?
			return snapshot.zoneAt(position.X, position.Y, position.Z, preferred)
		end,
		zoneOf = function(instance: Instance): number?
			return (rules.zoneOf(instance))
		end,
		zones = function(): { number }
			return table.clone(snapshot.zones)
		end,
		describe = describe,
		onChanged = function(listener: () -> ())
			table.insert(listeners, listener)
		end,
		refreshNow = refresh,
	})
end

return table.freeze(ZoneMap)

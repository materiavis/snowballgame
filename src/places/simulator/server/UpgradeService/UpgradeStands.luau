--!strict
-- Upgrade stands on the map (concept 7.8, ADR 0009, ADR 0010). Binds every `UpgradeStand`
-- station below Workspace.Map that StationRules accepts: a ProximityPrompt on its PrimaryPart.
-- The prompt changes no state. The client opens the same Upgrades window as U when a prompt
-- with the stand prompt tag triggers; buying still goes through the UpgradeBuy remote.
--
-- Invalid stations warn once per instance and are not bound. Nothing throws.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local StationRules = require(script.Parent:WaitForChild("StationRules"))

export type Options = {
	-- Config.Map
	map: any,
	-- Config.Ui.Text (prompt texts)
	text: any,
	worldIndex: number,
	zoneCount: number,
	isZone: (value: any) -> boolean,
	worldOf: (zone: number) -> number,
	log: (message: string) -> (),
}

export type Stands = {
	count: () -> number,
	-- Studio only (UpgradeStandTestGeometry): builds a valid test stand and two invalid ones in
	-- front of `origin`, or removes them. Returns a log line.
	setTestGeometry: (enabled: boolean, origin: CFrame?) -> string,
}

local TEST_AREA = "UpgradeStandTest"
local TEST_AREA_NO_ZONE = "UpgradeStandTestNoZone"

local UpgradeStands = {}

function UpgradeStands.start(options: Options): Stands
	local mapConfig = options.map
	local tag = mapConfig.Tags.UpgradeStand
	local promptConfig = mapConfig.UpgradeStand

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

	local prompts: { [Instance]: ProximityPrompt } = {}
	local warned: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local bound = 0

	local function bind(instance: Instance)
		if prompts[instance] then
			return
		end
		local verdict = rules.checkStation(instance)
		if verdict.status == "OutOfScope" then
			return
		end
		if verdict.status == "Invalid" then
			if not warned[instance] then
				warned[instance] = true
				warn(StationRules.warning(tag, instance:GetFullName(), verdict.problem or "invalid"))
			end
			return
		end
		local primary = (instance :: Model).PrimaryPart :: BasePart
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = promptConfig.PromptName
		prompt.ActionText = options.text.UpgradeStandAction
		prompt.ObjectText = options.text.UpgradeStandObject
		prompt.MaxActivationDistance = promptConfig.MaxActivationDistance
		prompt.HoldDuration = promptConfig.HoldDuration
		prompt.KeyboardKeyCode = (Enum.KeyCode :: any)[promptConfig.KeyboardKeyCode]
		prompt.GamepadKeyCode = (Enum.KeyCode :: any)[promptConfig.GamepadKeyCode]
		CollectionService:AddTag(prompt, promptConfig.PromptTag)
		prompt.Parent = primary
		prompts[instance] = prompt
		bound += 1
		options.log(`stand bound {instance:GetFullName()} zone={verdict.zone}`)
	end

	local function unbind(instance: Instance)
		local prompt = prompts[instance]
		if prompt == nil then
			return
		end
		prompts[instance] = nil
		bound -= 1
		prompt:Destroy()
		options.log(`stand unbound {instance:GetFullName()}`)
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbind)
	for _, instance in CollectionService:GetTagged(tag) do
		bind(instance)
	end

	-- The first zone of this world that no map area uses, so the test area never makes a real
	-- zone a duplicate.
	local function freeZone(folder: Instance): number?
		local used: { [any]: boolean } = {}
		for _, child in folder:GetChildren() do
			local value = child:GetAttribute(mapConfig.ZoneIndexAttribute)
			if value ~= nil then
				used[value] = true
			end
		end
		for zone = 1, options.zoneCount do
			if options.worldOf(zone) == options.worldIndex and not used[zone] then
				return zone
			end
		end
		return nil
	end

	local function stand(name: string, at: CFrame, withPrimary: boolean): Model
		local size = mapConfig.StandTest.PartSize
		local model = Instance.new("Model")
		model.Name = name
		model.ModelStreamingMode = (Enum.ModelStreamingMode :: any)[mapConfig.StationStreamingMode]
		local part = Instance.new("Part")
		part.Name = "Base"
		part.Anchored = true
		part.Size = Vector3.new(size[1], size[2], size[3])
		part.CFrame = at
		part.Parent = model
		if withPrimary then
			model.PrimaryPart = part
		end
		CollectionService:AddTag(model, tag)
		return model
	end

	local function setTestGeometry(enabled: boolean, origin: CFrame?): string
		local folder = mapFolder()
		if folder == nil then
			return `no Workspace.{mapConfig.FolderName}`
		end
		for _, name in { TEST_AREA, TEST_AREA_NO_ZONE } do
			local old = folder:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
		if not enabled then
			return "test stands removed"
		end
		local zone = freeZone(folder)
		if zone == nil or origin == nil then
			return "no free zone in this world or no character to place the test stands at"
		end
		local test = mapConfig.StandTest
		local front = origin * CFrame.new(0, 0, -test.Distance)
		local function beside(step: number): CFrame
			return front * CFrame.new(step * test.Spacing, 0, 0)
		end

		-- Built unparented and parented last, so the tag check sees the whole tree at once.
		local area = Instance.new("Folder")
		area.Name = TEST_AREA
		area:SetAttribute(mapConfig.ZoneIndexAttribute, zone)
		stand("UpgradeStand", beside(0), true).Parent = area
		stand("UpgradeStandNoPrimaryPart", beside(1), false).Parent = area

		local noZone = Instance.new("Folder")
		noZone.Name = TEST_AREA_NO_ZONE
		stand("UpgradeStandOutsideZone", beside(-1), true).Parent = noZone

		area.Parent = folder
		noZone.Parent = folder
		return `test stands built in {area:GetFullName()} (ZoneIndex {zone}) and {noZone:GetFullName()}`
	end

	return table.freeze({
		count = function(): number
			return bound
		end,
		setTestGeometry = setTestGeometry,
	})
end

return table.freeze(UpgradeStands)

--!strict
-- Find points on the map (concept 7.7, ADR 0009, ADR 0016). Binds every `FindPoint` anchor (an
-- Attachment or a BasePart) below Workspace.Map whose zone area has a valid ZoneIndex. The zone
-- comes from ZoneService's shared resolver (ADR 0014), not from a second lookup here. Like
-- every map binding (ADR 0009), the zone and the position are read once when the point binds;
-- points do not move.
--
-- Templates outside Workspace.Map are ignored silently; any other problem warns once per
-- instance (`[MapContract] FindPoint <full name>: <problem>, ignored`). Nothing throws.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local StationRules = require(script.Parent.Parent:WaitForChild("UpgradeService"):WaitForChild("StationRules"))

export type Options = {
	map: any, -- Config.Map
	zoneOf: (instance: Instance) -> number?, -- ZoneService.ZoneOfInstance
	onAdded: (instance: Instance, zone: number, position: Vector3) -> (),
	onRemoved: (instance: Instance) -> (),
}

export type Points = {
	count: () -> number,
}

local FindPoints = {}

-- World position of an anchor (ADR 0009 "Anchor"), or nil for any other kind of instance.
function FindPoints.positionOf(instance: Instance): Vector3?
	if instance:IsA("Attachment") then
		return instance.WorldPosition
	elseif instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

function FindPoints.start(options: Options): Points
	local tag = options.map.Tags.FindPoint
	local bound: { [Instance]: boolean } = {}
	local warned: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local count = 0

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
		local map = Workspace:FindFirstChild(options.map.FolderName)
		if map == nil or not instance:IsDescendantOf(map) then
			return
		end
		local position = FindPoints.positionOf(instance)
		if position == nil then
			warnOnce(instance, "a FindPoint must be an Attachment or a BasePart")
			return
		end
		local zone = options.zoneOf(instance)
		if zone == nil then
			warnOnce(instance, `not in a zone area with a valid {options.map.ZoneIndexAttribute}`)
			return
		end
		bound[instance] = true
		count += 1
		options.onAdded(instance, zone, position)
	end

	local function unbind(instance: Instance)
		if bound[instance] then
			bound[instance] = nil
			count -= 1
			options.onRemoved(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbind)
	for _, instance in CollectionService:GetTagged(tag) do
		bind(instance)
	end

	return table.freeze({
		count = function(): number
			return count
		end,
	})
end

return table.freeze(FindPoints)

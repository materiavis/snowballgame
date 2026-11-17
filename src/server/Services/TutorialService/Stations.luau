--!strict
-- The egg station and barrier targets of the onboarding hints (concept 10.1, ADR 0017). Reads
-- the ADR 0009 map contract read-only: `EggStation` / `Barrier` station Models below
-- Workspace.Map whose zone area has a valid, unique `ZoneIndex`. Binding, warnings and
-- purchases belong to the egg (#41) and barrier (#39) features; this module only looks, so an
-- invalid station is skipped without a warning (their services warn once).
--
-- When #39-#41 lift UpgradeService/StationRules into a shared resolver (ADR 0009 "Where the
-- names live in code"), this file should use it.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local TutorialCore = require(script.Parent:WaitForChild("TutorialCore"))

export type Options = {
	map: any, -- Config.Map
	isZone: (value: any) -> boolean,
	worldOf: (zone: number) -> number,
	worldIndex: number,
}

export type Stations = {
	inZone: (tag: string, zone: number) -> { Model },
	nearest: (models: { Model }, position: Vector3) -> (Model?, number),
}

local Stations = {}

function Stations.new(options: Options): Stations
	local map = options.map

	local function mapFolder(): Instance?
		return Workspace:FindFirstChild(map.FolderName)
	end

	-- The direct child of Workspace.Map holding `instance`, or nil outside the map.
	local function areaOf(root: Instance, instance: Instance): Instance?
		local current: Instance? = instance
		while current and current.Parent do
			if current.Parent == root then
				return current
			end
			current = current.Parent
		end
		return nil
	end

	local function zoneOfArea(root: Instance, area: Instance): number?
		local value = area:GetAttribute(map.ZoneIndexAttribute)
		if not options.isZone(value) or options.worldOf(value :: number) ~= options.worldIndex then
			return nil
		end
		for _, other in root:GetChildren() do
			if other ~= area and other:GetAttribute(map.ZoneIndexAttribute) == value then
				return nil -- ADR 0009: two areas with one ZoneIndex both have no zone
			end
		end
		return value :: number
	end

	local function inZone(tag: string, zone: number): { Model }
		local out: { Model } = {}
		local root = mapFolder()
		if root == nil then
			return out
		end
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("Model") and instance.PrimaryPart ~= nil then
				local area = areaOf(root, instance)
				if area and zoneOfArea(root, area) == zone then
					table.insert(out, instance)
				end
			end
		end
		return out
	end

	-- The model whose bounding box is closest to `position`, and that distance (math.huge if none).
	local function nearest(models: { Model }, position: Vector3): (Model?, number)
		local best: Model? = nil
		local bestDistance = math.huge
		for _, model in models do
			local frame, size = model:GetBoundingBox()
			local p = frame:PointToObjectSpace(position)
			local distance = TutorialCore.boxDistance(p.X, p.Y, p.Z, size.X, size.Y, size.Z)
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
		return best, bestDistance
	end

	return table.freeze({ inZone = inZone, nearest = nearest })
end

return table.freeze(Stations)

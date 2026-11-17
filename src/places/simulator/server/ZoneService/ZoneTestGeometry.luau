--!strict
-- Studio-only test zones for the switch ZoneTestGeometry (ADR 0014 "Studio playtest support").
-- The real zones 1-5 are built by people (#29); until then this builds ZoneTest01..ZoneTest06
-- under Workspace.Map, each a valid area of the map contract (ADR 0009): a Folder with
-- ZoneIndex n, a Snow-tagged floor, one ZoneStart Attachment and a Barrier station at its end.
-- ZoneTest06 exists so the cap test (#39 AC8) has a valid zone 6 in the map.
--
-- Sizes come from Config.Map.ZoneTest (test fixtures, not design values). Names use their own
-- prefix, so they never clash with the real ZoneNN areas or other features' test areas.

local CollectionService = game:GetService("CollectionService")

export type Options = {
	map: any, -- Config.Map
	snowTag: string, -- Config.Ball.Surfaces.Snow
}

local ZoneTestGeometry = {}

local COLOURS = {
	Color3.fromRGB(240, 244, 250),
	Color3.fromRGB(225, 236, 248),
	Color3.fromRGB(232, 228, 246),
	Color3.fromRGB(222, 244, 240),
	Color3.fromRGB(246, 236, 226),
	Color3.fromRGB(236, 236, 236),
}
local GATE_COLOUR = Color3.fromRGB(110, 190, 255)

local function areaName(options: Options, zone: number): string
	return string.format("%s%02d", options.map.ZoneTest.AreaPrefix, zone)
end

local function block(name: string, size: Vector3, cframe: CFrame, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = colour
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function buildArea(options: Options, zone: number): Folder
	local map = options.map
	local test = map.ZoneTest
	local origin = Vector3.new(test.Origin[1], test.Origin[2], test.Origin[3])
	local startX = origin.X + (zone - 1) * test.Length

	local area = Instance.new("Folder")
	area.Name = areaName(options, zone)
	area:SetAttribute(map.ZoneIndexAttribute, zone)

	local floor = block(
		"Floor",
		Vector3.new(test.Length, test.FloorThickness, test.Width),
		CFrame.new(startX + test.Length / 2, origin.Y - test.FloorThickness / 2, origin.Z),
		COLOURS[(zone - 1) % #COLOURS + 1]
	)
	floor.Material = Enum.Material.Snow
	CollectionService:AddTag(floor, options.snowTag)
	floor.Parent = area

	local start = Instance.new("Attachment")
	start.Name = "ZoneStart"
	start.Parent = floor
	local startPosition = Vector3.new(startX + test.StartInset, origin.Y, origin.Z)
	start.WorldCFrame = CFrame.lookAt(startPosition, startPosition + Vector3.xAxis)
	CollectionService:AddTag(start, map.Tags.ZoneStart)

	local barrier = Instance.new("Model")
	barrier.Name = "Barrier"
	barrier.ModelStreamingMode = (Enum.ModelStreamingMode :: any)[map.StationStreamingMode]
	local gateX = startX + test.Length - test.BarrierThickness / 2
	local gate = block(
		"Gate",
		Vector3.new(test.BarrierThickness, test.BarrierHeight, test.Width),
		CFrame.new(gateX, origin.Y + test.BarrierHeight / 2, origin.Z),
		GATE_COLOUR
	)
	gate.Material = Enum.Material.Neon
	gate.Transparency = test.BarrierTransparency
	gate.Parent = barrier
	local label = Instance.new("Attachment")
	label.Name = map.LabelAnchorName
	label.Position = Vector3.new(0, test.BarrierHeight / 2 + test.LabelHeight, 0)
	label.Parent = gate
	barrier.PrimaryPart = gate
	CollectionService:AddTag(barrier, map.Tags.Barrier)
	barrier.Parent = area

	return area
end

-- Builds the test zones under `folder` (Workspace.Map). Refuses, and changes nothing, when
-- another area already uses one of their ZoneIndex values (a real zone, or another test area
-- built first). Returns a log line.
function ZoneTestGeometry.create(folder: Instance, options: Options): string
	ZoneTestGeometry.remove(folder, options)
	local test = options.map.ZoneTest
	for _, child in folder:GetChildren() do
		local value = child:GetAttribute(options.map.ZoneIndexAttribute)
		if type(value) == "number" and value >= 1 and value <= test.Count then
			return `not built: {child:GetFullName()} already uses {options.map.ZoneIndexAttribute} {value}`
		end
	end
	-- Each area is built unparented and parented whole, so the map is read with complete areas.
	for zone = 1, test.Count do
		buildArea(options, zone).Parent = folder
	end
	local last = test.Origin[1] + test.Count * test.Length
	return `built {areaName(options, 1)}..{areaName(options, test.Count)} along +X from x={test.Origin[1]} to x={last}, z={test.Origin[3]} ± {test.Width / 2}`
end

function ZoneTestGeometry.remove(folder: Instance, options: Options)
	for zone = 1, options.map.ZoneTest.Count do
		local existing = folder:FindFirstChild(areaName(options, zone))
		if existing then
			existing:Destroy()
		end
	end
end

return table.freeze(ZoneTestGeometry)

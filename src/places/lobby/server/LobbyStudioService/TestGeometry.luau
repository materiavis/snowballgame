--!strict
-- Studio-only Lobby test layout (LobbyTestGeometry, ADR 0015). The real Lobby areas
-- (world/lobby/{Village,Plaza}.rbxmx) are human work and not built yet, so this builds every
-- Lobby entry of ADR 0009 as Workspace.Map.LobbyTest: a Grass floor, a LobbySpawn facing the
-- portals, the Singleplayer portal left and the Multiplayer portal right (both in the default
-- spawn camera's view), the group chest, the news board and the VIP corner. Positions and sizes
-- are Config.Lobby.Test (not design values). The real Plaza needs the same AC1 camera check.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

export type Options = {
	test: any, -- Config.Lobby.Test
	display: any, -- Config.Lobby.Display (colours)
	map: any, -- Config.Map
	grassTag: string, -- Config.Ball.Surfaces.Grass
	vipText: string, -- Config.Ui.Text.VipCornerSign
}

local FOLDER_NAME = "LobbyTest"

local TestGeometry = {}

local function vector(list: { number }): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

local function colour(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function part(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function station(name: string, tag: string, map: any, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = (Enum.ModelStreamingMode :: any)[map.StationStreamingMode]
	CollectionService:AddTag(model, tag)
	model.Parent = parent
	return model
end

local function portal(options: Options, origin: CFrame, mode: string, x: number, rgb: { number }, parent: Instance)
	local test, map = options.test, options.map
	local size = vector(test.PortalSize)
	local model = station(`Portal{mode}`, map.Tags.Portal, map, parent)
	model:SetAttribute(map.PortalModeAttribute, mode)

	local volume = part("Volume", size, origin * CFrame.new(x, size.Y / 2, -test.PortalDistance), model)
	volume.CanCollide = false
	volume.CanTouch = false
	volume.Material = Enum.Material.Neon
	volume.Color = colour(rgb)
	volume.Transparency = 0.85
	model.PrimaryPart = volume

	-- An upright disc behind the volume as the ring (Spielraum: portal effects). It collides, so
	-- walking in stops inside the volume.
	local diameter = test.PortalRingDiameter
	local ring = part(
		"Ring",
		Vector3.new(0.6, diameter, diameter),
		origin
			* CFrame.new(x, diameter / 2 + 0.5, -test.PortalDistance - size.Z / 2 - 0.5)
			* CFrame.Angles(0, math.rad(90), 0),
		model
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = colour(rgb)
	ring.Transparency = 0.3

	local anchor = Instance.new("Attachment")
	anchor.Name = map.LabelAnchorName
	anchor.Position = Vector3.new(0, size.Y / 2 + 4, 0)
	anchor.Parent = volume
end

-- Removes an old layout and builds a new one at Config.Lobby.Test.Origin. Returns a log line.
function TestGeometry.set(options: Options, enabled: boolean): string
	local map = options.map
	local folder = Workspace:FindFirstChild(map.FolderName)
	if folder == nil then
		return `no Workspace.{map.FolderName}`
	end
	local old = folder:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	if not enabled then
		return "Lobby test layout removed"
	end

	local test, display = options.test, options.display
	local origin = CFrame.new(vector(test.Origin))
	-- Built unparented and parented last, so every tag check sees the whole tree at once.
	local area = Instance.new("Folder")
	area.Name = FOLDER_NAME

	local floorSize = vector(test.FloorSize)
	local floor = part("Floor", floorSize, origin * CFrame.new(0, -floorSize.Y / 2, 0), area)
	floor.Material = Enum.Material.Grass
	floor.Color = Color3.fromRGB(90, 160, 70)
	CollectionService:AddTag(floor, options.grassTag)

	local spawnSize = vector(test.SpawnSize)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = spawnSize
	-- Identity rotation: the spawn and the character look along -z, at the portals.
	spawn.CFrame = origin * CFrame.new(0, spawnSize.Y / 2, 0)
	CollectionService:AddTag(spawn, map.Tags.LobbySpawn)
	spawn.Parent = area

	portal(options, origin, "Singleplayer", -test.PortalOffsetX, display.SingleplayerRGB, area)
	portal(options, origin, "Multiplayer", test.PortalOffsetX, display.MultiplayerRGB, area)

	local spawnPoint = origin.Position
	local function facingSpawn(offset: { number }, height: number): CFrame
		local at = origin * Vector3.new(offset[1], height, offset[3])
		return CFrame.lookAt(at, Vector3.new(spawnPoint.X, at.Y, spawnPoint.Z))
	end

	local chestSize = vector(test.ChestSize)
	local chest = station("GroupChest", map.Tags.GroupChest, map, area)
	local base = part("Base", chestSize, facingSpawn(test.ChestOffset, chestSize.Y / 2), chest)
	base.Color = Color3.fromRGB(140, 90, 40)
	base.Material = Enum.Material.WoodPlanks
	chest.PrimaryPart = base

	local newsSize = vector(test.NewsSize)
	local news = part("NewsBoard", newsSize, facingSpawn(test.NewsOffset, newsSize.Y / 2 + 1), area)
	news.Color = Color3.fromRGB(60, 45, 30)
	CollectionService:AddTag(news, map.Tags.NewsBoard)

	local vipSize = vector(test.VipSize)
	local vip =
		part("VipCornerVolume", vipSize, origin * CFrame.new(test.VipOffset[1], vipSize.Y / 2, test.VipOffset[3]), area)
	vip.CanCollide = false
	vip.CanTouch = false
	vip.Transparency = 0.8
	vip.Color = Color3.fromRGB(255, 200, 50)
	CollectionService:AddTag(vip, map.Tags.VipCorner)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromScale(6, 2)
	sign.StudsOffset = Vector3.new(0, vipSize.Y / 2 + 2, 0)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 200, 50)
	label.Text = options.vipText
	label.Parent = sign
	sign.Parent = vip

	area.Parent = folder
	return `Lobby test layout built in {area:GetFullName()} (spawn at {spawnPoint}, facing the portals)`
end

return table.freeze(TestGeometry)

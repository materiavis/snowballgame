--!strict
-- Studio-only playtest support for TutorialService (ADR 0017 "Studio playtest support").
-- TutorialService binds it only in Studio at game.PlaceId == 0. Switches on `host`
-- (ServerScriptService):
--   TutorialTargetUserId  number, the player the switches act on; 0 = every player
--   TutorialStudioReset   bool, true resets the target's tutorial hints in the live profile;
--                         resets itself to false
--   TutorialTestStations  number (Simulator): n builds Workspace.Map.TutorialTest with ZoneIndex
--                         n, an EggStation and a Barrier stand-in near the target; 0 removes it

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

export type Hooks = {
	reset: (player: Player) -> string,
}

export type Options = {
	map: any, -- Config.Map
	test: any, -- Config.Tutorial.Test
	isZone: (value: any) -> boolean,
	worldOf: (zone: number) -> number,
	worldIndex: number?, -- nil outside the Simulator: no test stations
	log: (message: string) -> (),
}

local TARGET_SWITCH = "TutorialTargetUserId"
local RESET_SWITCH = "TutorialStudioReset"
local STATIONS_SWITCH = "TutorialTestStations"

local TutorialSwitches = {}

TutorialSwitches.Names = table.freeze({
	Target = TARGET_SWITCH,
	Reset = RESET_SWITCH,
	TestStations = STATIONS_SWITCH,
})

local function default(host: Instance, name: string, value: any)
	if host:GetAttribute(name) == nil then
		host:SetAttribute(name, value)
	end
end

local function vector(list: { number }): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

local function colour(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function groundBelow(at: Vector3, exclude: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(at + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position.Y else nil
end

-- One tagged station Model (ADR 0009: tag on the Model, PrimaryPart, Atomic streaming).
local function stationModel(name: string, tag: string, map: any, size: Vector3, at: CFrame, rgb: { number }): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = (Enum.ModelStreamingMode :: any)[map.StationStreamingMode]
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.Size = size
	body.CFrame = at
	body.Color = colour(rgb)
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model
	model.PrimaryPart = body
	CollectionService:AddTag(model, tag)
	return model
end

function TutorialSwitches.bind(host: Instance, options: Options, hooks: Hooks)
	local map, test = options.map, options.test
	default(host, TARGET_SWITCH, 0)
	default(host, RESET_SWITCH, false)
	if options.worldIndex then
		default(host, STATIONS_SWITCH, 0)
	end

	local function targets(): { Player }
		local target = host:GetAttribute(TARGET_SWITCH)
		if type(target) == "number" and target ~= 0 then
			local player = Players:GetPlayerByUserId(target)
			if player == nil then
				warn(`[TutorialService] {TARGET_SWITCH}: no player with UserId {target}`)
				return {}
			end
			return { player }
		end
		return Players:GetPlayers()
	end

	host:GetAttributeChangedSignal(RESET_SWITCH):Connect(function()
		if host:GetAttribute(RESET_SWITCH) ~= true then
			return
		end
		host:SetAttribute(RESET_SWITCH, false)
		for _, player in targets() do
			options.log(`{RESET_SWITCH} {player.Name} ({player.UserId}): {hooks.reset(player)}`)
		end
	end)

	if not options.worldIndex then
		return
	end

	local function removeTest()
		local root = Workspace:FindFirstChild(map.FolderName)
		local old = root and root:FindFirstChild(test.AreaName)
		if old then
			old:Destroy()
		end
	end

	local function build(zone: number): string
		removeTest()
		if zone == 0 then
			return "test stations removed"
		end
		local root = Workspace:FindFirstChild(map.FolderName)
		if root == nil then
			return `not built: no Workspace.{map.FolderName}`
		end
		if not options.isZone(zone) or options.worldOf(zone) ~= options.worldIndex then
			return `not built: {zone} is not a zone of world {options.worldIndex}`
		end
		for _, child in root:GetChildren() do
			if child:GetAttribute(map.ZoneIndexAttribute) == zone then
				return `not built: {child:GetFullName()} already has {map.ZoneIndexAttribute} {zone}`
			end
		end
		local player = targets()[1]
		local character = player and player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp == nil or not hrp:IsA("BasePart") or character == nil then
			return "not built: no character to place the stations at"
		end
		local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if look.Magnitude < 1e-3 then
			look = Vector3.new(0, 0, -1)
		end
		local frame = CFrame.lookAt(hrp.Position, hrp.Position + look)

		local area = Instance.new("Folder")
		area.Name = test.AreaName
		area:SetAttribute(map.ZoneIndexAttribute, zone)
		local lines = {}
		for _, entry in
			{
				{
					name = "EggStation",
					tag = map.Tags.EggStation,
					offset = test.EggOffset,
					size = test.EggSize,
					rgb = test.EggRGB,
				},
				{
					name = "Barrier",
					tag = map.Tags.Barrier,
					offset = test.BarrierOffset,
					size = test.BarrierSize,
					rgb = test.BarrierRGB,
				},
			}
		do
			local at = frame * CFrame.new(vector(entry.offset))
			local size = vector(entry.size)
			local groundY = groundBelow(at.Position, { character })
			if groundY == nil then
				return `not built: no ground under the {entry.name} stand-in`
			end
			local placed = CFrame.lookAt(
				Vector3.new(at.Position.X, groundY + size.Y / 2, at.Position.Z),
				Vector3.new(hrp.Position.X, groundY + size.Y / 2, hrp.Position.Z)
			)
			local model = stationModel(entry.name, entry.tag, map, size, placed, entry.rgb)
			model.Parent = area
			table.insert(lines, `{entry.name} at {string.format("%.1f, %.1f, %.1f", placed.X, placed.Y, placed.Z)}`)
		end
		-- Parented last, so every reader sees the whole area at once.
		area.Parent = root
		return `built {area:GetFullName()} ({map.ZoneIndexAttribute} {zone}): {table.concat(lines, "; ")}`
	end

	host:GetAttributeChangedSignal(STATIONS_SWITCH):Connect(function()
		local zone = host:GetAttribute(STATIONS_SWITCH)
		if type(zone) ~= "number" or zone % 1 ~= 0 or zone < 0 then
			warn(`[TutorialService] {STATIONS_SWITCH}: expected 0 or a zone number, got {tostring(zone)}`)
			return
		end
		options.log(`{STATIONS_SWITCH} {zone} -> {build(zone)}`)
	end)
end

return table.freeze(TutorialSwitches)

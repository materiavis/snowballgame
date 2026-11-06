--!strict
-- Builds and places the ball part for BallService (ADR 0002): where a ball spawns in front of
-- the character and what the part looks like. Roblox-facing; every number and look comes
-- from Config.Ball.

export type BallPart = {
	spawnPosition: (root: BasePart, diameter: number) -> Vector3,
	create: (player: Player, diameter: number, position: Vector3, parent: Instance) -> Part,
}

local BallPartModule = {}

-- `holdDistance` is BallCore.holdDistance; `groundParams` is BallService's ground filter
-- (all balls and characters excluded), shared so both always see the same ground.
function BallPartModule.new(
	config: any,
	holdDistance: (diameter: number) -> number,
	groundParams: RaycastParams
): BallPart
	local rgb = config.ColorRGB
	local color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	local material = (Enum.Material :: any)[config.MaterialName]
	assert(material ~= nil, `Config.Ball.MaterialName is not an Enum.Material: {config.MaterialName}`)

	-- Centre for a ball of the given diameter, on the ground at the hold distance in front of
	-- the character, so it starts where the client holds it.
	local function spawnPosition(root: BasePart, diameter: number): Vector3
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if look.Magnitude < 1e-3 then
			look = Vector3.new(0, 0, -1)
		end
		local spot = root.Position + look.Unit * holdDistance(diameter)
		local height = config.SpawnGroundSearchHeight
		local origin = Vector3.new(spot.X, root.Position.Y + height, spot.Z)
		local ray = Vector3.new(0, -height * config.SpawnGroundSearchDepthFactor, 0)
		local result = workspace:Raycast(origin, ray, groundParams)
		local groundY = if result then result.Position.Y else root.Position.Y - config.SpawnFallbackGroundOffset
		return Vector3.new(spot.X, groundY + diameter / 2, spot.Z)
	end

	local function create(player: Player, diameter: number, position: Vector3, parent: Instance): Part
		local part = Instance.new("Part")
		part.Name = "Ball_" .. player.UserId
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * diameter
		part.Material = material
		part.Color = color
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CustomPhysicalProperties = PhysicalProperties.new(
			config.Density,
			config.Friction,
			config.Elasticity,
			config.FrictionWeight,
			config.ElasticityWeight
		)
		-- Server view: every ball is in Balls. Clients reassign locally (CollisionController).
		part.CollisionGroup = config.CollisionGroups.Balls
		part.CFrame = CFrame.new(position)
		part:SetAttribute(config.OwnerAttribute, player.UserId)
		part.Parent = parent
		return part
	end

	return table.freeze({
		spawnPosition = spawnPosition,
		create = create,
	})
end

return table.freeze(BallPartModule)

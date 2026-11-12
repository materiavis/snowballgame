--!strict
-- Finds where BallService puts a ball back (concept 7.3, ADR 0002 "Recovery", issue #94).
-- Roblox-facing; the rules are in RecoveryRules. Only server state is read: the character's
-- replicated root part and the world. No client value is used.
--
-- Order: candidates around the character (front first), then the ball's last safe position,
-- then the old placement in front ("Unsafe", warned by Recovery).

local CollectionService = game:GetService("CollectionService")

export type Kind = "Front" | "Around" | "LastSafe" | "Unsafe"

export type Spot = {
	position: Vector3,
	kind: Kind,
}

export type SafeSpot = {
	find: (root: BasePart, diameter: number, lastSafe: Vector3?) -> Spot,
}

export type Deps = {
	config: any,
	recoveryRules: any,
	obstacleRules: any,
	growthRules: any,
	holdDistance: (diameter: number) -> number,
	-- The old placement in front (BallPart.spawnPosition), used when nothing is safe.
	fallback: (root: BasePart, diameter: number) -> Vector3,
	-- BallService's ground filter: every ball and every character excluded.
	groundParams: RaycastParams,
}

local SafeSpotModule = {}

function SafeSpotModule.new(deps: Deps): SafeSpot
	local config = deps.config
	local recoveryRules = deps.recoveryRules
	-- Own parameters: the search only stands on and avoids collidable parts, unlike the
	-- surface ray, which also reads non-colliding snow patches.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.RespectCanCollide = true

	local function syncFilter()
		local excluded = deps.groundParams.FilterDescendantsInstances
		rayParams.FilterDescendantsInstances = excluded
		overlapParams.FilterDescendantsInstances = excluded
	end

	local function isObstacle(instance: Instance): boolean
		return CollectionService:HasTag(instance, config.ObstacleTag)
	end

	-- Ground height below (x, z) searched from `topY` down and the Y of its surface normal, or
	-- nil. The top of an obstacle is not ground: a ball put there would count a collision on
	-- the first push.
	local function groundAt(x: number, z: number, topY: number, depth: number): (number?, number)
		local result = workspace:Raycast(Vector3.new(x, topY, z), Vector3.new(0, -depth, 0), rayParams)
		if result == nil or isObstacle(result.Instance) then
			return nil, 0
		end
		return result.Position.Y, result.Normal.Y
	end

	-- Exact for obstacles (box rule, as in Obstacles) and plain blocks. Other shapes (wedges,
	-- meshes, terrain) cannot be measured by their box without false hits on slopes, so the
	-- ground and support rays are their only check.
	local function overlapsSomething(centre: Vector3, radius: number): boolean
		local reach = radius + config.RecoveryObstacleClearance
		for _, part in workspace:GetPartBoundsInRadius(centre, reach, overlapParams) do
			local obstacle = isObstacle(part)
			if not obstacle and not (part:IsA("Part") and part.Shape == Enum.PartType.Block) then
				continue
			end
			local localPoint = part.CFrame:PointToObjectSpace(centre)
			local half = part.Size / 2
			local distance =
				deps.obstacleRules.boxDistance(localPoint.X, localPoint.Y, localPoint.Z, half.X, half.Y, half.Z)
			if recoveryRules.blocksPlacement(distance, radius, obstacle) then
				return true
			end
		end
		return false
	end

	-- Centre of a ball resting on the ground below (x, z), or nil if it would not stay there.
	local function probe(x: number, z: number, searchY: number, diameter: number): Vector3?
		local radius = diameter / 2
		local height = config.SpawnGroundSearchHeight
		local centreGround, normalY = groundAt(x, z, searchY + height, height * config.SpawnGroundSearchDepthFactor)
		if centreGround == nil then
			return nil
		end
		-- On a slope the centre is radius / cos(slope) above the hit; at radius it would reach
		-- into the slope and the overlap check below would reject every spot on a ramp (#94).
		local centreY = recoveryRules.restingHeight(centreGround, normalY, radius)
		if centreY == nil then
			return nil
		end
		-- Support rays start at the centre's height, so an overhang above cannot answer for them.
		local depth = (centreY - centreGround) + radius * config.RecoverySupportShare * config.RecoverySupportSlope + 1
		-- By index: a missing ground is a nil that table.insert would drop.
		local supports: { [number]: number? } = {}
		for index, offset in recoveryRules.supportOffsets(radius) do
			supports[index] = (groundAt(x + offset.x, z + offset.z, centreY, depth))
		end
		if not recoveryRules.isSupported(centreGround, supports, radius) then
			return nil
		end
		local centre = Vector3.new(x, centreY, z)
		if overlapsSomething(centre, radius) then
			return nil
		end
		return centre
	end

	local function find(root: BasePart, diameter: number, lastSafe: Vector3?): Spot
		syncFilter()
		local rootPosition = root.Position
		local look = root.CFrame.LookVector
		for _, candidate in recoveryRules.candidates(look.X, look.Z, deps.holdDistance(diameter)) do
			local centre = probe(rootPosition.X + candidate.x, rootPosition.Z + candidate.z, rootPosition.Y, diameter)
			-- Ground far below (a cliff) or above is out of the character's reach: not a put-back spot.
			if centre then
				local horizontal = math.sqrt(candidate.x * candidate.x + candidate.z * candidate.z)
				if deps.growthRules.inGrowthRange(horizontal, rootPosition.Y - centre.Y, diameter) then
					return { position = centre, kind = if candidate.bearing == 0 then "Front" else "Around" }
				end
			end
		end
		if lastSafe then
			local centre = probe(lastSafe.X, lastSafe.Z, lastSafe.Y, diameter)
			if centre then
				return { position = centre, kind = "LastSafe" }
			end
		end
		return { position = deps.fallback(root, diameter), kind = "Unsafe" }
	end

	return table.freeze({
		find = find,
	})
end

return table.freeze(SafeSpotModule)

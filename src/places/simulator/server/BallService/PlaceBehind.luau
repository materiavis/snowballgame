--!strict
-- Studio switch BallPlaceBehindObstacle (ADR 0002 "Playtest hooks", issue #94 AC8). Puts the
-- target's ball on the far side of the Obstacle nearest to the character, on the line from
-- the character through the obstacle, just clear of it. The client hold then presses it into
-- the obstacle: held behind it, out of growth range, inside the leash, so the stuck rule is
-- what puts it back. BallService binds this only in Studio at PlaceId 0.
--
-- Not a recovery: it does not count Recoveries or the bounds and prints no recovery line.
-- The sizes below are test tooling, not gameplay values.

local PlaceBehind = {}

local SEARCH_STEP = 0.25 -- studs between tries along the line behind the obstacle
-- The character must stand at most this far from the obstacle's box (ground plane and
-- height), so the ball behind it stays inside the leash.
local MAX_OBSTACLE_REACH = 6

export type Deps = {
	config: any,
	obstacleRules: any,
	recoveryRules: any,
	growthRules: any,
	holdDistance: (diameter: number) -> number,
	groundParams: RaycastParams,
	-- Every Obstacle-tagged part currently in the world.
	obstacles: () -> { Instance },
	moveTo: (state: any, position: Vector3) -> (),
}

-- Smallest t in [0, limit], in steps of `step`, at which `distanceAt(t)` (ball centre to the
-- obstacle's box, nil = no ground there) reaches `clear`. nil if none.
function PlaceBehind.clearDistance(
	distanceAt: (t: number) -> number?,
	clear: number,
	step: number,
	limit: number
): number?
	local t = 0
	while t <= limit do
		local distance = distanceAt(t)
		if distance ~= nil and distance >= clear then
			return t
		end
		t += step
	end
	return nil
end

local function show(position: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

function PlaceBehind.new(deps: Deps): (state: any) -> ()
	local config = deps.config

	local function boxDistance(part: BasePart, point: Vector3): number
		local localPoint = part.CFrame:PointToObjectSpace(point)
		local half = part.Size / 2
		return deps.obstacleRules.boxDistance(localPoint.X, localPoint.Y, localPoint.Z, half.X, half.Y, half.Z)
	end

	local function nearestObstacle(rootPosition: Vector3): BasePart?
		local best: BasePart? = nil
		local bestDistance = MAX_OBSTACLE_REACH
		for _, instance in deps.obstacles() do
			if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
				local distance = boxDistance(instance, rootPosition)
				if distance <= bestDistance then
					best, bestDistance = instance, distance
				end
			end
		end
		return best
	end

	-- Centre of the ball resting on the ground below (x, z), searched from `fromY` down.
	local function restingCentre(x: number, z: number, fromY: number, radius: number): Vector3?
		local height = config.SpawnGroundSearchHeight
		local origin = Vector3.new(x, fromY + height, z)
		local hit = workspace:Raycast(
			origin,
			Vector3.new(0, -height * config.SpawnGroundSearchDepthFactor, 0),
			deps.groundParams
		)
		if hit == nil then
			return nil
		end
		local y = deps.recoveryRules.restingHeight(hit.Position.Y, hit.Normal.Y, radius)
		return if y then Vector3.new(x, y, z) else nil
	end

	return function(state: any)
		local name = state.player.Name
		local root: BasePart? = state.root
		local part: BasePart? = state.part
		local humanoid: Humanoid? = state.humanoid
		local prefix = `[BallService] {name} BallPlaceBehindObstacle`
		if not root or not root.Parent or not humanoid or humanoid.Health <= 0 or not part or not part.Parent then
			warn(`{prefix}: needs a living character and a ball`)
			return
		end
		if state.parkedUntil ~= nil then
			warn(`{prefix}: the ball is parked by the recovery bound, try again after the release`)
			return
		end
		local rootPosition = root.Position
		local obstacle = nearestObstacle(rootPosition)
		if obstacle == nil then
			warn(`{prefix}: no Obstacle within {MAX_OBSTACLE_REACH} studs of the character at {show(rootPosition)}`)
			return
		end
		local away = obstacle.Position - rootPosition
		local direction = Vector3.new(away.X, 0, away.Z)
		if direction.Magnitude < 1e-3 then
			warn(`{prefix}: the character stands on {obstacle.Name}`)
			return
		end
		direction = direction.Unit
		local diameter = part.Size.X
		local radius = diameter / 2
		local base = obstacle.Position
		local function centreAt(t: number): Vector3?
			local point = base + direction * t
			return restingCentre(point.X, point.Z, rootPosition.Y, radius)
		end
		local clear = radius + config.RecoveryObstacleClearance
		local limit = obstacle.Size.Magnitude / 2 + clear + 1
		local t = PlaceBehind.clearDistance(function(distanceT: number): number?
			local centre = centreAt(distanceT)
			return if centre then boxDistance(obstacle, centre) else nil
		end, clear, SEARCH_STEP, limit)
		local centre = if t then centreAt(t) else nil
		if centre == nil then
			warn(`{prefix}: no ground behind {obstacle.Name}`)
			return
		end
		local offset = centre - rootPosition
		local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
		local leashMargin = config.LeashDistance - (horizontal - deps.holdDistance(diameter))
		if leashMargin <= 0 then
			warn(
				`{prefix}: the ball would be beyond the leash ({string.format("%.1f", -leashMargin)} studs), stand closer`
			)
			return
		end
		deps.moveTo(state, centre)
		local inRange = deps.growthRules.inGrowthRange(horizontal, -offset.Y, diameter)
		print(
			`{prefix} -> ball={show(centre)} character={show(rootPosition)} obstacle={obstacle.Name} gap={string.format(
				"%.2f",
				boxDistance(obstacle, centre) - radius
			)} growthRange={if inRange then "in" else "out"} leashMargin={string.format("%.1f", leashMargin)}`
		)
	end
end

return table.freeze(PlaceBehind)

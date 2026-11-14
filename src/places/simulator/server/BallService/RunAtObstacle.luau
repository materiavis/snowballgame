--!strict
-- Studio switch BallRunAtObstacle (ADR 0002 "Playtest hooks", issue #97). Lines the target up
-- in front of the named Obstacle and walks the character into it, so the run A hits can be
-- repeated the same way every time, at any ball size, without keyboard input: the character
-- stands RUN_UP studs of ball travel before the obstacle's +Z side, facing -Z, the ball at its
-- hold distance in front; after LINE_UP_SETTLE seconds Humanoid:MoveTo walks the character
-- towards a point behind the obstacle. It keeps pushing until Roblox ends the MoveTo (8 s)
-- or a key is pressed. BallService binds this only in Studio at PlaceId 0.
--
-- Not a recovery: the ball is moved like BallPlaceBehindObstacle (Placements +1, so the client
-- hold turns to it). The sizes below are test tooling, not gameplay values.

local PlaceBehind = require(script.Parent:WaitForChild("PlaceBehind"))

local RunAtObstacle = {}

local APPROACH = Vector3.new(0, 0, -1) -- the character walks along -Z into the obstacle
-- Studs between the ball's surface and the obstacle at the start. 24 studs at walk speed 16
-- take about 1.5 s, so the placement's CollisionProtection (1 s) is over at the hit.
local RUN_UP = 24
local SEARCH_STEP = 0.25
-- Seconds before the walk starts: the client hold follows the moved ball for
-- RecoveryHoldResetTime (0.5 s) first, so it starts in front.
local LINE_UP_SETTLE = 0.6

export type Deps = {
	config: any,
	obstacleRules: any,
	recoveryRules: any,
	holdDistance: (diameter: number) -> number,
	groundParams: RaycastParams,
	obstacles: () -> { Instance },
	moveTo: (state: any, position: Vector3) -> (),
}

local function show(position: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

function RunAtObstacle.new(deps: Deps): (state: any, obstacleName: string) -> ()
	local config = deps.config

	local function boxDistance(part: BasePart, point: Vector3): number
		local localPoint = part.CFrame:PointToObjectSpace(point)
		local half = part.Size / 2
		return deps.obstacleRules.boxDistance(localPoint.X, localPoint.Y, localPoint.Z, half.X, half.Y, half.Z)
	end

	local function find(name: string): BasePart?
		for _, instance in deps.obstacles() do
			if instance.Name == name and instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
				return instance
			end
		end
		return nil
	end

	-- Ground hit below (x, z), searched from `fromY` down.
	local function groundAt(x: number, z: number, fromY: number): RaycastResult?
		local height = config.SpawnGroundSearchHeight
		return workspace:Raycast(
			Vector3.new(x, fromY + height, z),
			Vector3.new(0, -height * config.SpawnGroundSearchDepthFactor, 0),
			deps.groundParams
		)
	end

	return function(state: any, obstacleName: string)
		local name = state.player.Name
		local prefix = `[BallService] {name} BallRunAtObstacle`
		local root: BasePart? = state.root
		local humanoid: Humanoid? = state.humanoid
		local part: BasePart? = state.part
		if not root or not root.Parent or not humanoid or humanoid.Health <= 0 or not part or not part.Parent then
			warn(`{prefix}: needs a living character and a ball`)
			return
		end
		if state.parkedUntil ~= nil then
			warn(`{prefix}: the ball is parked by the recovery bound, try again after the release`)
			return
		end
		local obstacle = find(obstacleName)
		if obstacle == nil then
			warn(`{prefix}: no Obstacle named "{obstacleName}" in the world (knocked over?)`)
			return
		end
		local diameter = part.Size.X
		local radius = diameter / 2
		local behind = -APPROACH
		local fromY = obstacle.Position.Y
		local function centreAt(t: number): Vector3?
			local point = obstacle.Position + behind * t
			local hit = groundAt(point.X, point.Z, fromY)
			if hit == nil then
				return nil
			end
			local y = deps.recoveryRules.restingHeight(hit.Position.Y, hit.Normal.Y, radius)
			return if y then Vector3.new(point.X, y, point.Z) else nil
		end
		local clear = radius + RUN_UP
		local limit = obstacle.Size.Magnitude / 2 + clear + 1
		local t = PlaceBehind.clearDistance(function(distanceT: number): number?
			local centre = centreAt(distanceT)
			return if centre then boxDistance(obstacle, centre) else nil
		end, clear, SEARCH_STEP, limit)
		local ball = if t then centreAt(t) else nil
		if ball == nil then
			warn(`{prefix}: no ground in front of {obstacleName}`)
			return
		end
		local standAt = ball + behind * deps.holdDistance(diameter)
		local ground = groundAt(standAt.X, standAt.Z, ball.Y)
		if ground == nil then
			warn(`{prefix}: no ground for the character in front of {obstacleName}`)
			return
		end
		local rootPosition = Vector3.new(standAt.X, ground.Position.Y + humanoid.HipHeight + root.Size.Y / 2, standAt.Z)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(rootPosition, rootPosition + APPROACH)
		deps.moveTo(state, ball)
		local walkTo = obstacle.Position + APPROACH * (obstacle.Size.Magnitude / 2 + clear)
		print(
			`{prefix} -> obstacle={obstacleName} ball={show(ball)} character={show(rootPosition)} diameter={string.format(
				"%.2f",
				diameter
			)} runUp={RUN_UP} walkTo={show(walkTo)} in {LINE_UP_SETTLE} s`
		)
		local walker: Humanoid = humanoid
		task.delay(LINE_UP_SETTLE, function()
			if walker.Parent and walker.Health > 0 and state.root == root then
				walker:MoveTo(Vector3.new(walkTo.X, rootPosition.Y, walkTo.Z))
			end
		end)
	end
end

return table.freeze(RunAtObstacle)

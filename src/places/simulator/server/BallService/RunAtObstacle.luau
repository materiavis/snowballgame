--!strict
-- Studio switch BallRunAtObstacle (ADR 0002 "Playtest hooks", issue #97). Lines the target up
-- in front of the named Obstacle and walks the character into it, so the run A hits can be
-- repeated the same way every time, at any ball size, without keyboard input.
--
-- Value: "<name>" or "<name>,<offset>" or "<name>,<offset>,<angle>". The walk aims at the
-- point `offset` studs along +X from the obstacle's centre, coming from its +Z side, along -Z
-- turned `angle` degrees towards +X (#97 round 1: by hand the character is rarely on the
-- centre line nor walking exactly along -Z, and only that off-centre case slid the ball along
-- the face). The ball starts RUN_UP studs of ball travel before the obstacle on that line, the
-- character at its hold distance behind it, facing the walk; after LINE_UP_SETTLE seconds
-- Humanoid:MoveTo walks the character past the obstacle along the line. It keeps pushing until
-- Roblox ends the MoveTo (8 s) or a key is pressed. BallService binds this only in Studio at
-- PlaceId 0.
--
-- Not a recovery: the ball is moved like BallPlaceBehindObstacle (Placements +1, so the client
-- hold turns to it). The sizes below are test tooling, not gameplay values.

local RunAtObstacle = {}

-- Studs between the ball's surface and the obstacle at the start. 24 studs at walk speed 16
-- take about 1.5 s, so the placement's CollisionProtection (1 s) is over at the hit.
local RUN_UP = 24
local SEARCH_STEP = 0.25
-- Seconds before the walk starts: the client hold follows the moved ball for
-- RecoveryHoldResetTime (0.5 s) first, so it starts in front.
local LINE_UP_SETTLE = 0.6
local MAX_OFFSET = 50 -- studs
local MAX_ANGLE = 45 -- degrees

export type Run = {
	name: string,
	offset: number,
	angle: number,
}

export type Deps = {
	config: any,
	obstacleRules: any,
	recoveryRules: any,
	holdDistance: (diameter: number) -> number,
	groundParams: RaycastParams,
	obstacles: () -> { Instance },
	moveTo: (state: any, position: Vector3) -> (),
	-- PlaceBehind.clearDistance
	clearDistance: (distanceAt: (t: number) -> number?, clear: number, step: number, limit: number) -> number?,
}

local function isFinite(value: number?): boolean
	return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

-- Parses the switch value; nil and a reason for nonsense.
function RunAtObstacle.parse(value: string): (Run?, string?)
	local parts = string.split(value, ",")
	local name = string.gsub(parts[1] or "", "^%s*(.-)%s*$", "%1")
	if name == "" or #parts > 3 then
		return nil, `expected "<name>[,<offset>[,<angle>]]", got "{value}"`
	end
	local offset = if parts[2] then tonumber(parts[2]) else 0
	local angle = if parts[3] then tonumber(parts[3]) else 0
	if not isFinite(offset) or math.abs(offset :: number) > MAX_OFFSET then
		return nil, `offset must be a number of studs within ±{MAX_OFFSET}, got "{parts[2]}"`
	end
	if not isFinite(angle) or math.abs(angle :: number) > MAX_ANGLE then
		return nil, `angle must be a number of degrees within ±{MAX_ANGLE}, got "{parts[3]}"`
	end
	return { name = name, offset = offset :: number, angle = angle :: number }, nil
end

local function show(position: Vector3): string
	return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

function RunAtObstacle.new(deps: Deps): (state: any, value: string) -> ()
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

	return function(state: any, value: string)
		local name = state.player.Name
		local prefix = `[BallService] {name} BallRunAtObstacle`
		local run, problem = RunAtObstacle.parse(value)
		if run == nil then
			warn(`{prefix}: {problem}`)
			return
		end
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
		local obstacle = find(run.name)
		if obstacle == nil then
			warn(`{prefix}: no Obstacle named "{run.name}" in the world (knocked over?)`)
			return
		end
		local diameter = part.Size.X
		local radius = diameter / 2
		local angle = math.rad(run.angle)
		local walk = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local aim = obstacle.Position + Vector3.new(run.offset, 0, 0)
		local fromY = obstacle.Position.Y
		local function centreAt(t: number): Vector3?
			local point = aim - walk * t
			local hit = groundAt(point.X, point.Z, fromY)
			if hit == nil then
				return nil
			end
			local y = deps.recoveryRules.restingHeight(hit.Position.Y, hit.Normal.Y, radius)
			return if y then Vector3.new(point.X, y, point.Z) else nil
		end
		local clear = radius + RUN_UP
		local limit = obstacle.Size.Magnitude / 2 + clear + 1
		local t = deps.clearDistance(function(distanceT: number): number?
			local centre = centreAt(distanceT)
			return if centre then boxDistance(obstacle, centre) else nil
		end, clear, SEARCH_STEP, limit)
		local ball = if t then centreAt(t) else nil
		if ball == nil then
			warn(`{prefix}: no ground in front of {run.name}`)
			return
		end
		local standAt = ball - walk * deps.holdDistance(diameter)
		local ground = groundAt(standAt.X, standAt.Z, ball.Y)
		if ground == nil then
			warn(`{prefix}: no ground for the character in front of {run.name}`)
			return
		end
		local rootPosition = Vector3.new(standAt.X, ground.Position.Y + humanoid.HipHeight + root.Size.Y / 2, standAt.Z)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(rootPosition, rootPosition + walk)
		deps.moveTo(state, ball)
		local walkTo = aim + walk * (obstacle.Size.Magnitude / 2 + clear)
		local setup = `offset={run.offset} angle={run.angle} diameter={string.format("%.2f", diameter)} runUp={RUN_UP}`
		print(
			`{prefix} -> obstacle={run.name} ball={show(ball)} character={show(rootPosition)} {setup} walkTo={show(
				walkTo
			)} in {LINE_UP_SETTLE} s`
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

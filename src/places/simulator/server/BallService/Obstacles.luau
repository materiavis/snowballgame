--!strict
-- Finds the obstacles a ball touches and knocks small ones over (concept 7.4, ADR 0002).
-- Roblox-facing; the rules are in ObstacleRules.
--
-- The server measures the contact itself from the replicated ball position. Touched on a
-- client-owned part is reported by that client, and an exploiting owner could leave it out.

local CollectionService = game:GetService("CollectionService")

local ObstacleRules = require(script.Parent:WaitForChild("ObstacleRules"))

export type Obstacles = {
	start: (ballsFolder: Instance) -> (),
	contactsAt: (position: Vector3, radius: number) -> { ObstacleRules.Contact },
	-- Gap in studs between a ball's surface and the obstacle's box; nil once it is out of the
	-- world (knocked over or destroyed). For the same-hit memory (#97).
	gapTo: (obstacle: BasePart, position: Vector3, radius: number) -> number?,
	knockOver: (obstacle: BasePart) -> (),
}

local ObstaclesModule = {}

function ObstaclesModule.new(config: any, rules: ObstacleRules.ObstacleRules, verbose: boolean): Obstacles
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	local tracked: { Instance } = {}
	local knockedOver: { [BasePart]: boolean } = {}
	local balls: Instance

	local function refreshFilter()
		tracked = CollectionService:GetTagged(config.ObstacleTag)
		overlapParams.FilterDescendantsInstances = tracked
	end

	local function boxDistance(obstacle: BasePart, position: Vector3): number
		local localPoint = obstacle.CFrame:PointToObjectSpace(position)
		local half = obstacle.Size / 2
		return rules.boxDistance(localPoint.X, localPoint.Y, localPoint.Z, half.X, half.Y, half.Z)
	end

	local function touches(obstacle: BasePart, position: Vector3, radius: number): boolean
		return rules.isTouching(boxDistance(obstacle, position), radius)
	end

	local function gapTo(obstacle: BasePart, position: Vector3, radius: number): number?
		if not obstacle:IsDescendantOf(workspace) then
			return nil
		end
		return boxDistance(obstacle, position) - radius
	end

	local function contactsAt(position: Vector3, radius: number): { ObstacleRules.Contact }
		local found: { ObstacleRules.Contact } = {}
		if #tracked == 0 then
			return found
		end
		local reach = radius + config.CollisionContactMargin
		for _, part in workspace:GetPartBoundsInRadius(position, reach, overlapParams) do
			if touches(part, position, radius) then
				table.insert(found, {
					obstacle = part,
					knockOverSize = part:GetAttribute(config.KnockOverSizeAttribute),
				})
			end
		end
		return found
	end

	-- A returning obstacle must not appear inside a ball: the solver would throw the ball out
	-- and the ball would count it as a fresh collision.
	local function isBallAt(obstacle: BasePart): boolean
		for _, ball in balls:GetChildren() do
			if ball:IsA("BasePart") and touches(obstacle, ball.Position, ball.Size.X / 2) then
				return true
			end
		end
		return false
	end

	local function bringBack(obstacle: BasePart, parent: Instance)
		if parent.Parent == nil then
			knockedOver[obstacle] = nil
			return
		end
		if isBallAt(obstacle) then
			task.delay(config.KnockOverRetryInterval, bringBack, obstacle, parent)
			return
		end
		knockedOver[obstacle] = nil
		obstacle.Parent = parent
		if verbose then
			print(`[BallService] obstacle {obstacle.Name} is back`)
		end
	end

	-- Taken out of the world for every player and kept for its return.
	local function knockOver(obstacle: BasePart)
		local parent = obstacle.Parent
		if knockedOver[obstacle] or parent == nil then
			return
		end
		knockedOver[obstacle] = true
		obstacle.Parent = nil
		task.delay(config.KnockOverRespawn, bringBack, obstacle, parent)
		if verbose then
			print(`[BallService] obstacle {obstacle.Name} knocked over, back in {config.KnockOverRespawn} s`)
		end
	end

	local function start(ballsFolder: Instance)
		balls = ballsFolder
		CollectionService:GetInstanceAddedSignal(config.ObstacleTag):Connect(refreshFilter)
		CollectionService:GetInstanceRemovedSignal(config.ObstacleTag):Connect(refreshFilter)
		refreshFilter()
	end

	return table.freeze({
		start = start,
		contactsAt = contactsAt,
		gapTo = gapTo,
		knockOver = knockOver,
	})
end

return table.freeze(ObstaclesModule)

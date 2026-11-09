--!strict
-- Pure camera distances for "the ball is always fully in view" (concept 7.3). No Instances,
-- so `lune run tests` checks them; CameraController binds them to Config.Ball.

local CameraFit = {}

-- Narrower half field of view in radians. Roblox FieldOfView is vertical; on a portrait phone
-- the horizontal one is the narrower.
function CameraFit.narrowHalfAngle(verticalFovDegrees: number, aspect: number): number
	local verticalHalf = math.rad(verticalFovDegrees) / 2
	local horizontalHalf = math.atan(math.tan(verticalHalf) * aspect)
	return math.min(verticalHalf, horizontalHalf)
end

-- Distance from the camera focus to the farthest point of a ball resting on the ground,
-- `holdDistance` away horizontally on any bearing. The focus height is a range because the
-- worst height differs: a big ball's centre is above the focus, a small one's far below it.
function CameraFit.ballReach(
	radius: number,
	holdDistance: number,
	focusHeightMin: number,
	focusHeightMax: number
): number
	local vertical = math.max(math.abs(radius - focusHeightMin), math.abs(radius - focusHeightMax))
	return radius + math.sqrt(holdDistance * holdDistance + vertical * vertical)
end

-- Smallest camera-to-focus distance that keeps the ball fully in view. The camera aims at the
-- character, not at the ball, so the ball is off-axis. Every point of the ball lies within
-- `ballReach` of the focus, and a sphere of radius R around the view axis fits the cone of half
-- angle a from distance R / sin(a). That holds for every ball bearing and camera pitch.
function CameraFit.requiredZoom(
	diameter: number,
	holdDistance: number,
	verticalFovDegrees: number,
	aspect: number,
	margin: number,
	focusHeightMin: number,
	focusHeightMax: number
): number
	if diameter <= 0 then
		return 0
	end
	local safeAspect = if aspect > 0 and aspect == aspect then aspect else 1
	local half = CameraFit.narrowHalfAngle(verticalFovDegrees, safeAspect)
	return CameraFit.ballReach(diameter / 2, holdDistance, focusHeightMin, focusHeightMax) / math.sin(half) * margin
end

-- Whether the camera is closer to its focus than the ball allows. The tolerance keeps the
-- per-frame work (one raycast) off while the default camera already sits at the minimum.
function CameraFit.needsPush(currentDistance: number, requiredDistance: number, tolerance: number): boolean
	return requiredDistance > 0 and currentDistance < requiredDistance - tolerance
end

-- Camera distance after pushing it back to `requiredDistance`, stopping `wallClearance` before
-- a wall at `wallDistance` (nil: nothing in the way). Never pulls the camera in: closer than
-- the current distance is the default camera's call.
function CameraFit.pushedDistance(
	currentDistance: number,
	requiredDistance: number,
	wallDistance: number?,
	wallClearance: number
): number
	local reachable = if wallDistance
		then math.min(requiredDistance, wallDistance - wallClearance)
		else requiredDistance
	return math.max(currentDistance, reachable)
end

return table.freeze(CameraFit)

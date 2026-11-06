--!strict
-- Pure camera distance for "the ball is always fully in view" (concept 7.3). No Instances,
-- so `lune run tests` checks it; CameraController binds it to Config.Ball.

local CameraFit = {}

-- Narrower half field of view in radians. Roblox FieldOfView is vertical; on a portrait phone
-- the horizontal one is the narrower.
function CameraFit.narrowHalfAngle(verticalFovDegrees: number, aspect: number): number
	local verticalHalf = math.rad(verticalFovDegrees) / 2
	local horizontalHalf = math.atan(math.tan(verticalHalf) * aspect)
	return math.min(verticalHalf, horizontalHalf)
end

-- Smallest camera-to-character zoom distance that keeps a ball of `diameter` fully in view.
-- A sphere of radius r fits in a cone of half angle a from distance r / sin(a). The ball's
-- centre is `holdDistance` from the character, towards or away from the camera depending on
-- where the player turned it, so the worst case (ball between camera and character) is added.
function CameraFit.requiredZoom(
	diameter: number,
	holdDistance: number,
	verticalFovDegrees: number,
	aspect: number,
	margin: number
): number
	if diameter <= 0 then
		return 0
	end
	local safeAspect = if aspect > 0 and aspect == aspect then aspect else 1
	local half = CameraFit.narrowHalfAngle(verticalFovDegrees, safeAspect)
	local radius = diameter / 2
	return radius / math.sin(half) * margin + holdDistance
end

return table.freeze(CameraFit)

--!strict
-- Pure camera distances for "the ball is always fully in view" (concept 7.3). No Instances,
-- so `lune run tests` checks them; CameraController binds them to Config.Ball.
--
-- Issue #95 (ADR 0002 "Camera"): `viewZoom` is exact for the current view and drives the
-- per-frame push, so the whole ball stays in view at every bearing and pitch. The player's zoom
-- minimum is only `minimumZoom`, what the usual view (ball ahead, camera level or looking down)
-- needs, so a small ball can be looked at from close up.

local CameraFit = {}

-- Narrower half field of view in radians. Roblox FieldOfView is vertical; on a portrait phone
-- the horizontal one is the narrower.
function CameraFit.narrowHalfAngle(verticalFovDegrees: number, aspect: number): number
	local verticalHalf = math.rad(verticalFovDegrees) / 2
	local horizontalHalf = math.atan(math.tan(verticalHalf) * aspect)
	return math.min(verticalHalf, horizontalHalf)
end

-- Vertical and horizontal half field of view in radians. A broken aspect counts as square
-- instead of turning every distance into NaN.
function CameraFit.halfAngles(verticalFovDegrees: number, aspect: number): (number, number)
	local safeAspect = if aspect > 0 and aspect == aspect then aspect else 1
	local verticalHalf = math.rad(verticalFovDegrees) / 2
	return verticalHalf, math.atan(math.tan(verticalHalf) * safeAspect)
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

-- Worst case over every view: every point of the ball lies within `ballReach` of the focus, and
-- a sphere of radius R around the view axis fits the cone of half angle a from R / sin(a). It
-- only sizes the zoom room (CameraMaxZoomDistance), so zooming out is never capped below what
-- the push may need.
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

-- Exact distance from the focus along the view at which the whole ball sits inside the four
-- side planes of the picture, each clearing it by `clearance` studs. (cx, cy, cz) is the ball
-- centre minus the focus; look, up and right are the camera's unit vectors. A side plane through
-- the camera at focus - z * look has the inward normal n = sin(a) * look ± cos(a) * edge, so the
-- ball centre lies n.c + z * sin(a) inside it, which must be at least radius + clearance. The
-- four planes together are the whole picture. Plain numbers, so the per-frame push allocates
-- nothing.
function CameraFit.viewZoom(
	cx: number,
	cy: number,
	cz: number,
	radius: number,
	clearance: number,
	lookX: number,
	lookY: number,
	lookZ: number,
	upX: number,
	upY: number,
	upZ: number,
	rightX: number,
	rightY: number,
	rightZ: number,
	verticalHalf: number,
	horizontalHalf: number
): number
	if radius <= 0 then
		return 0
	end
	local forward = cx * lookX + cy * lookY + cz * lookZ
	local up = math.abs(cx * upX + cy * upY + cz * upZ)
	local side = math.abs(cx * rightX + cy * rightY + cz * rightZ)
	local sinV, cosV = math.sin(verticalHalf), math.cos(verticalHalf)
	local sinH, cosH = math.sin(horizontalHalf), math.cos(horizontalHalf)
	local need = radius + clearance
	local vertical = (need - (forward * sinV - up * cosV)) / sinV
	local horizontal = (need - (forward * sinH - side * cosH)) / sinH
	return math.max(vertical, horizontal, 0)
end

-- `viewZoom` for a ball resting on the ground `holdDistance` from the character, with the
-- camera at `pitch` (radians, positive looks up) and the ball at `bearing` (radians, 0 = straight
-- ahead along the view), for the worse focus height. The need is a maximum of absolute values
-- of linear functions of the focus height, so convex: the ends of the range bound the middle.
function CameraFit.restingViewZoom(
	diameter: number,
	holdDistance: number,
	clearance: number,
	pitch: number,
	bearing: number,
	verticalHalf: number,
	horizontalHalf: number,
	focusHeightMin: number,
	focusHeightMax: number
): number
	local radius = diameter / 2
	local lookX, lookY = math.cos(pitch), math.sin(pitch)
	local upX, upY = -math.sin(pitch), math.cos(pitch)
	local cx, cz = math.cos(bearing) * holdDistance, math.sin(bearing) * holdDistance
	local low = CameraFit.viewZoom(
		cx,
		radius - focusHeightMin,
		cz,
		radius,
		clearance,
		lookX,
		lookY,
		0,
		upX,
		upY,
		0,
		0,
		0,
		1,
		verticalHalf,
		horizontalHalf
	)
	local high = CameraFit.viewZoom(
		cx,
		radius - focusHeightMax,
		cz,
		radius,
		clearance,
		lookX,
		lookY,
		0,
		upX,
		upY,
		0,
		0,
		0,
		1,
		verticalHalf,
		horizontalHalf
	)
	return math.max(low, high)
end

-- The player's zoom minimum: the usual view, the camera behind the character and the ball ahead
-- of it (bearing 0), fits the whole ball at every pitch from `pitchMinDegrees` (looking down) to
-- `pitchMaxDegrees`. Any other view (ball beside or between, camera looking up) is pushed out
-- every frame by `viewZoom`, so this is a comfort floor, not the in-view guarantee. Runs on
-- size, field-of-view and viewport changes, not per frame.
function CameraFit.minimumZoom(
	diameter: number,
	holdDistance: number,
	verticalFovDegrees: number,
	aspect: number,
	clearance: number,
	focusHeightMin: number,
	focusHeightMax: number,
	pitchMinDegrees: number,
	pitchMaxDegrees: number,
	stepDegrees: number
): number
	if diameter <= 0 or stepDegrees <= 0 then
		return 0
	end
	local verticalHalf, horizontalHalf = CameraFit.halfAngles(verticalFovDegrees, aspect)
	local worst = 0
	for pitchDegrees = pitchMinDegrees, pitchMaxDegrees, stepDegrees do
		local zoom = CameraFit.restingViewZoom(
			diameter,
			holdDistance,
			clearance,
			math.rad(pitchDegrees),
			0,
			verticalHalf,
			horizontalHalf,
			focusHeightMin,
			focusHeightMax
		)
		worst = math.max(worst, zoom)
	end
	return worst
end

-- Whether the camera is closer to its focus than the ball allows. The tolerance keeps the
-- per-frame work (one raycast) off while the default camera already sits far enough out.
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

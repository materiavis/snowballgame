--!strict
-- CameraFit (issue #33 AC3): the zoom keeps the whole ball in view at every size, screen shape,
-- ball bearing and camera pitch, and the push out of the default occlusion respects walls.

local fs = require("@lune/fs")

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local ZonesConfig = require("../../../../src/shared/Config/Zones")
local E = require("../../../helpers/Economy")
local CameraFit = require("../../../../src/places/simulator/client/CameraController/CameraFit")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")

local hold = HoldMath.new(BallConfig :: any)
local FOV = 70 -- Roblox default Camera.FieldOfView
local ASPECTS = { 16 / 9, 4 / 3, 9 / 19.5, 2.5 } -- PC, tablet, portrait phone, wide
local FRACTIONS = { 0, 0.5, 1 } -- sizes inside a zone
local FOCUS_HEIGHTS = { 3, 4.5, 6 } -- studs above the ground the ball rests on
-- Every frustum plane must clear the ball by at least this share of its diameter.
local MIN_CLEARANCE_SHARE = 0.1
local ROBLOX_DEFAULT_MAX_ZOOM = 400

local CONTROLLER_PATH = "src/places/simulator/client/CameraController/init.luau"

local function zoomFor(diameter: number, aspect: number): number
	return CameraFit.requiredZoom(
		diameter,
		hold.holdDistance(diameter),
		FOV,
		aspect,
		BallConfig.CameraFitMargin,
		BallConfig.CameraFocusHeightMin,
		BallConfig.CameraFocusHeightMax
	)
end

-- Smallest distance by which the ball stays inside the four side planes of a camera that looks
-- at a focus above the character. Negative means part of the ball is outside the picture.
local function frustumClearance(
	diameter: number,
	zoom: number,
	aspect: number,
	pitch: number,
	bearing: number,
	focusHeight: number
): number
	local radius = diameter / 2
	local holdDistance = hold.holdDistance(diameter)
	local verticalHalf = math.rad(FOV) / 2
	local horizontalHalf = math.atan(math.tan(verticalHalf) * aspect)

	-- Camera basis with the view in the x/y plane; the bearing sweep covers every yaw.
	local lookX, lookY = math.cos(pitch), math.sin(pitch)
	local upX, upY = -math.sin(pitch), math.cos(pitch)

	-- Ball centre relative to the camera at focus - zoom * look.
	local dx = math.cos(bearing) * holdDistance + zoom * lookX
	local dy = radius - focusHeight + zoom * lookY
	local dz = math.sin(bearing) * holdDistance

	local forward = dx * lookX + dy * lookY
	local up = dx * upX + dy * upY

	local verticalEdge = forward * math.sin(verticalHalf) - math.abs(up) * math.cos(verticalHalf)
	local horizontalEdge = forward * math.sin(horizontalHalf) - math.abs(dz) * math.cos(horizontalHalf)
	return math.min(verticalEdge, horizontalEdge) - radius
end

return T.suite("Simulator CameraFit (7.3)", function(test)
	test("the narrower half angle is the vertical one in landscape, horizontal in portrait", function()
		T.near(CameraFit.narrowHalfAngle(FOV, 16 / 9), math.rad(35), 1e-9, "landscape")
		T.isTrue(CameraFit.narrowHalfAngle(FOV, 0.5) < math.rad(35), "portrait")
	end)

	test("the ball reach is the farthest point of the ball from the focus", function()
		-- Big ball: centre 25 up, focus at 3: 22 vertical, 26.5 horizontal.
		T.near(CameraFit.ballReach(25, 26.5, 3, 6), 25 + math.sqrt(26.5 ^ 2 + 22 ^ 2), 1e-9, "big ball")
		-- Small ball: centre 0.8 up, focus at 6: 5.2 vertical, the high focus is the worst.
		T.near(CameraFit.ballReach(0.8, 2.3, 3, 6), 0.8 + math.sqrt(2.3 ^ 2 + 5.2 ^ 2), 1e-9, "small ball")
	end)

	test("AC3: every frustum plane contains the whole ball with a real margin", function()
		local startFraction = ZonesConfig.OpticsStartFraction
		for zone = 1, E.Zones.zoneCount do
			local zoneDiameter = E.Zones.zoneOptics(zone)
			for _, fraction in FRACTIONS do
				local diameter = zoneDiameter * (startFraction + (1 - startFraction) * fraction)
				local required = diameter * MIN_CLEARANCE_SHARE
				for _, aspect in ASPECTS do
					local zoom = zoomFor(diameter, aspect)
					for _, focusHeight in FOCUS_HEIGHTS do
						for pitchDegrees = -80, 80, 5 do
							for bearingDegrees = 0, 345, 15 do
								local clearance = frustumClearance(
									diameter,
									zoom,
									aspect,
									math.rad(pitchDegrees),
									math.rad(bearingDegrees),
									focusHeight
								)
								T.isTrue(
									clearance >= required,
									`zone {zone} fraction {fraction} aspect {aspect} focus {focusHeight} `
										.. `pitch {pitchDegrees} bearing {bearingDegrees}: {clearance} < {required}`
								)
							end
						end
					end
				end
			end
		end
	end)

	test("the zoom grows with the ball", function()
		local previous = 0
		for zone = 1, E.Zones.zoneCount do
			local zoom = zoomFor(E.Zones.zoneOptics(zone), 16 / 9)
			T.isTrue(zoom > previous, `zone {zone}`)
			previous = zoom
		end
	end)

	test("the portrait zoom at the Visual Cap leaves room below Roblox's default maximum", function()
		local zoom = zoomFor(ZonesConfig.VisualCap, 9 / 19.5)
		T.isTrue(zoom + BallConfig.CameraMaxZoomExtra <= ROBLOX_DEFAULT_MAX_ZOOM, `zoom {zoom}`)
	end)

	test("a broken aspect falls back to square instead of NaN", function()
		local zoom = CameraFit.requiredZoom(4, hold.holdDistance(4), FOV, 0 / 0, 1, 3, 6)
		T.isTrue(zoom == zoom and zoom > 0)
		T.equal(CameraFit.requiredZoom(0, 1, FOV, 1, 1, 3, 6), 0)
	end)

	test("too close: the camera is pushed out to the required distance", function()
		T.isTrue(CameraFit.needsPush(2, 100, 0.05))
		T.equal(CameraFit.pushedDistance(2, 100, nil, 0.5), 100)
	end)

	test("already far enough: the camera stays where it is", function()
		T.isTrue(not CameraFit.needsPush(150, 100, 0.05), "beyond the distance")
		T.isTrue(not CameraFit.needsPush(99.99, 100, 0.05), "inside the tolerance")
		T.isTrue(not CameraFit.needsPush(5, 0, 0.05), "no ball")
		T.equal(CameraFit.pushedDistance(150, 100, nil, 0.5), 150)
	end)

	test("a wall in between: the camera stops before it and is never pulled in", function()
		T.equal(CameraFit.pushedDistance(2, 100, 40, 0.5), 39.5, "stops before the wall")
		T.equal(CameraFit.pushedDistance(2, 100, 200, 0.5), 100, "wall beyond the distance")
		T.equal(CameraFit.pushedDistance(39.8, 100, 40, 0.5), 39.8, "already at the wall")
	end)

	test("the push runs right after the camera and allocates no table per frame", function()
		local source = fs.readFile(CONTROLLER_PATH)
		T.isTrue(string.find(source, "Enum.RenderPriority.Camera.Value + 1", 1, true) ~= nil, "priority")
		local body = string.match(source, "local function pushCameraOut%(%)(.-)\nend\n")
		T.isTrue(body ~= nil, "render step found")
		T.isTrue(string.find(body :: string, "{", 1, true) == nil, "no table constructor")
	end)
end)

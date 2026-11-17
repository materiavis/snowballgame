--!strict
-- CameraFit (issue #33 AC3, #95): the per-view push keeps the whole ball in view at every size,
-- screen shape, ball bearing and camera pitch, the small-ball minimum is lower, and the push out
-- of the default occlusion respects walls.

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

local AC1_DIAMETERS = { 1.6, 4, 50 }
local AC3_DIAMETERS = { 1.6, 26.56, 50 }
local AC_ASPECTS = { 16 / 9, 9 / 19.5 }

-- The player's zoom minimum (#95).
local function minimumFor(diameter: number, aspect: number): number
	return CameraFit.minimumZoom(
		diameter,
		hold.holdDistance(diameter),
		FOV,
		aspect,
		diameter * BallConfig.CameraFitClearanceShare,
		BallConfig.CameraFocusHeightMin,
		BallConfig.CameraFocusHeightMax,
		BallConfig.CameraMinZoomPitchMinDegrees,
		BallConfig.CameraMinZoomPitchMaxDegrees,
		BallConfig.CameraMinZoomStepDegrees
	)
end

-- The distance the per-frame push keeps for one view and one real focus height.
local function viewZoomAt(
	diameter: number,
	pitch: number,
	bearing: number,
	focusHeight: number,
	verticalHalf: number,
	horizontalHalf: number
): number
	return CameraFit.restingViewZoom(
		diameter,
		hold.holdDistance(diameter),
		diameter * BallConfig.CameraFitClearanceShare,
		pitch,
		bearing,
		verticalHalf,
		horizontalHalf,
		focusHeight,
		focusHeight
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

	test("the worst-case zoom (zoom room above) contains the whole ball in every view", function()
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

	test("#95 AC3: at the per-view push distance every frustum plane clears the ball", function()
		local startFraction = ZonesConfig.OpticsStartFraction
		for zone = 1, E.Zones.zoneCount do
			local zoneDiameter = E.Zones.zoneOptics(zone)
			for _, fraction in FRACTIONS do
				local diameter = zoneDiameter * (startFraction + (1 - startFraction) * fraction)
				local need = diameter * MIN_CLEARANCE_SHARE - 1e-6
				local worst = zoomFor(diameter, 16 / 9)
				for _, aspect in ASPECTS do
					local verticalHalf, horizontalHalf = CameraFit.halfAngles(FOV, aspect)
					worst = zoomFor(diameter, aspect)
					for _, focusHeight in FOCUS_HEIGHTS do
						for pitchDegrees = -80, 80, 5 do
							for bearingDegrees = 0, 345, 15 do
								local pitch, bearing = math.rad(pitchDegrees), math.rad(bearingDegrees)
								local zoom =
									viewZoomAt(diameter, pitch, bearing, focusHeight, verticalHalf, horizontalHalf)
								local clearance = frustumClearance(diameter, zoom, aspect, pitch, bearing, focusHeight)
								local where = `zone {zone} fraction {fraction} aspect {aspect} focus {focusHeight} `
									.. `pitch {pitchDegrees} bearing {bearingDegrees}`
								T.isTrue(clearance >= need, `{where}: {clearance} < {need}`)
								-- The zoom room above (max zoom) always covers the push.
								T.isTrue(zoom <= worst + 1e-6, `{where}: view {zoom} > worst {worst}`)
							end
						end
					end
				end
			end
		end
	end)

	test("#95 AC3: every silhouette point of the ball is in the picture at 1.6, 26.56 and 50", function()
		for _, diameter in AC3_DIAMETERS do
			local radius = diameter / 2
			local holdDistance = hold.holdDistance(diameter)
			for _, aspect in AC_ASPECTS do
				local verticalHalf, horizontalHalf = CameraFit.halfAngles(FOV, aspect)
				local tanV, tanH = math.tan(verticalHalf), math.tan(horizontalHalf)
				for _, focusHeight in FOCUS_HEIGHTS do
					for pitchDegrees = -80, 80, 10 do
						-- 0 in front, 90/270 beside, 180 between camera and character.
						for bearingDegrees = 0, 345, 15 do
							local pitch, bearing = math.rad(pitchDegrees), math.rad(bearingDegrees)
							local zoom = viewZoomAt(diameter, pitch, bearing, focusHeight, verticalHalf, horizontalHalf)
							local lookX, lookY = math.cos(pitch), math.sin(pitch)
							local upX, upY = -math.sin(pitch), math.cos(pitch)
							-- Ball centre relative to the camera.
							local bx = math.cos(bearing) * holdDistance + zoom * lookX
							local by = radius - focusHeight + zoom * lookY
							local bz = math.sin(bearing) * holdDistance
							local inside = true
							for latitude = -90, 90, 15 do
								local ring = math.cos(math.rad(latitude)) * radius
								local py = by + math.sin(math.rad(latitude)) * radius
								for longitude = 0, 345, 15 do
									local px = bx + math.cos(math.rad(longitude)) * ring
									local pz = bz + math.sin(math.rad(longitude)) * ring
									local forward = px * lookX + py * lookY
									local up = px * upX + py * upY
									if
										forward <= 0
										or math.abs(up) > forward * tanV
										or math.abs(pz) > forward * tanH
									then
										inside = false
									end
								end
							end
							T.isTrue(
								inside,
								`diameter {diameter} aspect {aspect} focus {focusHeight} pitch {pitchDegrees} `
									.. `bearing {bearingDegrees} zoom {zoom}`
							)
						end
					end
				end
			end
		end
	end)

	test("#95 AC1: the small-ball minimum is below 12.44 in landscape", function()
		local zoom = minimumFor(1.6, 16 / 9)
		T.isTrue(zoom < 12.44, `minimum {zoom}`)
		for _, diameter in AC1_DIAMETERS do
			for _, aspect in AC_ASPECTS do
				-- Farthest the push takes the camera for a resting ball (any view, focus 3..6).
				local verticalHalf, horizontalHalf = CameraFit.halfAngles(FOV, aspect)
				local pushed = 0
				for pitchDegrees = -80, 80, 5 do
					for bearingDegrees = 0, 345, 15 do
						pushed = math.max(
							pushed,
							CameraFit.restingViewZoom(
								diameter,
								hold.holdDistance(diameter),
								diameter * BallConfig.CameraFitClearanceShare,
								math.rad(pitchDegrees),
								math.rad(bearingDegrees),
								verticalHalf,
								horizontalHalf,
								BallConfig.CameraFocusHeightMin,
								BallConfig.CameraFocusHeightMax
							)
						)
					end
				end
				print(
					string.format(
						"  [AC1] diameter %.2f aspect %.3f: old min %.2f, new min %.2f, farthest push %.2f",
						diameter,
						aspect,
						zoomFor(diameter, aspect),
						minimumFor(diameter, aspect),
						pushed
					)
				)
			end
		end
	end)

	test("#95: in the usual view the minimum already fits, so only other views are pushed", function()
		for _, diameter in AC1_DIAMETERS do
			for _, aspect in AC_ASPECTS do
				local verticalHalf, horizontalHalf = CameraFit.halfAngles(FOV, aspect)
				local minimum = minimumFor(diameter, aspect)
				T.isTrue(minimum > 0 and minimum <= zoomFor(diameter, aspect), `diameter {diameter} aspect {aspect}`)
				for _, focusHeight in FOCUS_HEIGHTS do
					for pitchDegrees = BallConfig.CameraMinZoomPitchMinDegrees, BallConfig.CameraMinZoomPitchMaxDegrees do
						local zoom =
							viewZoomAt(diameter, math.rad(pitchDegrees), 0, focusHeight, verticalHalf, horizontalHalf)
						T.isTrue(
							zoom <= minimum + 1e-6,
							`diameter {diameter} aspect {aspect} focus {focusHeight} pitch {pitchDegrees}: {zoom}`
						)
					end
				end
			end
		end
	end)

	test("viewZoom is zero without a ball and never negative", function()
		T.equal(CameraFit.viewZoom(1, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0.6, 0.6), 0)
		-- A tiny ball far in front of the camera needs no distance at all.
		T.equal(CameraFit.viewZoom(100, 0, 0, 0.1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0.6, 0.6), 0)
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

	test("#95 R1: an occluded camera at a 50-stud ball returns at least to the minimum", function()
		local diameter = 50
		local minimum = minimumFor(diameter, 16 / 9)
		local tolerance = BallConfig.CameraPushTolerance
		local wallClearance = BallConfig.CameraWallClearance
		-- Poppercam pulled the camera to 5 studs in front of the ball.
		local occluded = 5
		local below = CameraFit.pushTarget(minimum - 11, minimum)
		T.equal(below, minimum, "viewZoom below the minimum: the minimum")
		T.isTrue(CameraFit.needsPush(occluded, below, tolerance), "pushed")
		T.equal(CameraFit.pushedDistance(occluded, below, nil, wallClearance), minimum, "back to the minimum")
		local above = CameraFit.pushTarget(minimum + 20, minimum)
		T.equal(above, minimum + 20, "viewZoom above the minimum: viewZoom")
		T.equal(CameraFit.pushedDistance(occluded, above, nil, wallClearance), minimum + 20)
		-- A wall closer than both still stops the push (documented limit).
		T.equal(CameraFit.pushedDistance(occluded, below, 60, wallClearance), 60 - wallClearance, "wall")
		T.equal(CameraFit.pushedDistance(occluded, above, 60, wallClearance), 60 - wallClearance, "wall")
		-- A camera already at the minimum is left alone.
		T.isTrue(not CameraFit.needsPush(minimum, below, tolerance), "at the minimum")
	end)

	test("#95 R1: turning a 50-stud ball through 150..180 degrees never moves the camera off the minimum", function()
		local diameter = 50
		local tolerance = BallConfig.CameraPushTolerance
		local belowMinimum = 0
		for _, aspect in AC_ASPECTS do
			local verticalHalf, horizontalHalf = CameraFit.halfAngles(FOV, aspect)
			local minimum = minimumFor(diameter, aspect)
			for _, focusHeight in FOCUS_HEIGHTS do
				for pitchDegrees = -80, 0, 5 do
					-- The camera sits occluded every frame; the push decides where it ends up.
					local previous = nil :: number?
					for bearingDegrees = 150, 180 do
						local view = viewZoomAt(
							diameter,
							math.rad(pitchDegrees),
							math.rad(bearingDegrees),
							focusHeight,
							verticalHalf,
							horizontalHalf
						)
						local target = CameraFit.pushTarget(view, minimum)
						local distance = CameraFit.pushedDistance(5, target, nil, BallConfig.CameraWallClearance)
						local where =
							`aspect {aspect} focus {focusHeight} pitch {pitchDegrees} bearing {bearingDegrees}`
						T.isTrue(distance >= minimum - tolerance, `{where}: {distance} below {minimum}`)
						if view < minimum then
							belowMinimum += 1
							T.isTrue(math.abs(distance - minimum) <= tolerance, `{where}: {distance} off {minimum}`)
						end
						if previous and view < minimum then
							T.isTrue(math.abs(distance - previous) <= tolerance or previous > minimum, where)
						end
						previous = distance
					end
				end
			end
		end
		-- The playtest case (viewZoom about 101 under a 112.09 minimum) is really covered.
		T.isTrue(belowMinimum > 0, "some view needs less than the minimum")
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

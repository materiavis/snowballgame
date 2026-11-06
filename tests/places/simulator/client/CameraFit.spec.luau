--!strict
-- CameraFit (issue #33 AC3): the zoom keeps the whole ball in view at every size, in landscape
-- and portrait, also when the camera looks at the character from in front of the ball.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local E = require("../../../helpers/Economy")
local CameraFit = require("../../../../src/places/simulator/client/CameraController/CameraFit")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")

local hold = HoldMath.new(BallConfig :: any)
local FOV = 70 -- Roblox default Camera.FieldOfView
local ASPECTS = { 16 / 9, 4 / 3, 9 / 19.5 } -- PC, tablet, portrait phone

local function zoomFor(diameter: number, aspect: number): number
	return CameraFit.requiredZoom(diameter, hold.holdDistance(diameter), FOV, aspect, BallConfig.CameraFitMargin)
end

return T.suite("Simulator CameraFit (7.3)", function(test)
	test("the narrower half angle is the vertical one in landscape, horizontal in portrait", function()
		T.near(CameraFit.narrowHalfAngle(FOV, 16 / 9), math.rad(35), 1e-9, "landscape")
		T.isTrue(CameraFit.narrowHalfAngle(FOV, 0.5) < math.rad(35), "portrait")
	end)

	test("AC3: the whole ball fits in view for every zone size and screen", function()
		for zone = 1, E.Zones.zoneCount do
			local diameter = E.Zones.zoneOptics(zone)
			for _, aspect in ASPECTS do
				local zoom = zoomFor(diameter, aspect)
				local radius = diameter / 2
				-- Worst case: the ball sits between camera and character.
				local cameraToBall = zoom - hold.holdDistance(diameter)
				local half = CameraFit.narrowHalfAngle(FOV, aspect)
				T.isTrue(radius / cameraToBall <= math.sin(half), `zone {zone} aspect {aspect}`)
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

	test("a broken aspect falls back to square instead of NaN", function()
		local zoom = CameraFit.requiredZoom(4, hold.holdDistance(4), FOV, 0 / 0, 1)
		T.isTrue(zoom == zoom and zoom > 0)
		T.equal(CameraFit.requiredZoom(0, 1, FOV, 1, 1), 0)
	end)
end)

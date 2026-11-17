--!strict
-- Whether a ball touches a scale plate, and when it counts as having left it (#38, ADR 0012).

local T = require("../../../TestKit")
local SellConfig = require("../../../../src/shared/Config/Sell")
local PlateGeometry = require("../../../../src/places/simulator/server/SellService/PlateGeometry")

-- The test plate: 16 x 1 x 16 studs.
local HX, HY, HZ = 8, 0.5, 8

local function classify(x: number, y: number, z: number, radius: number): (boolean, boolean)
	local distance = PlateGeometry.boxDistance(x, y, z, HX, HY, HZ)
	return PlateGeometry.classify(PlateGeometry.gap(distance, radius), SellConfig)
end

return T.suite("SellService.PlateGeometry (ADR 0012)", function(test)
	test("box distance: 0 inside, straight and diagonal outside", function()
		T.equal(PlateGeometry.boxDistance(0, 0, 0, HX, HY, HZ), 0)
		T.equal(PlateGeometry.boxDistance(0, 3.5, 0, HX, HY, HZ), 3)
		T.near(PlateGeometry.boxDistance(11, 0, 12, HX, HY, HZ), 5, 1e-12)
	end)

	test("a ball resting on the plate touches it, at every size", function()
		for _, radius in { 0.5, 2, 10, 60 } do
			-- Resting on the top face; a little solver penetration or float noise either way.
			for _, sink in { -0.05, 0, 0.1 } do
				local touching, clear = classify(3, HY + radius - sink, -2, radius)
				T.equal(touching, true, `radius {radius} sink {sink}`)
				T.equal(clear, false)
			end
		end
	end)

	test("a ball beside the plate: touching at the edge, clear only past ReleaseMargin", function()
		local radius = 2
		local function at(gap: number): (boolean, boolean)
			return classify(HX + radius + gap, 0, 0, radius)
		end
		T.equal(select(1, at(0)), true)
		T.equal(select(1, at(SellConfig.TouchMargin)), true)
		local touching, clear = at(1)
		T.equal(touching, false, "1 stud away is not touching")
		T.equal(clear, false, "but not clear yet: no flip at the edge")
		T.equal(select(2, at(SellConfig.ReleaseMargin + 0.01)), true)
		T.isTrue(SellConfig.ReleaseMargin > SellConfig.TouchMargin)
	end)

	test("no plates: math.huge is clear and not touching", function()
		local touching, clear = PlateGeometry.classify(math.huge, SellConfig)
		T.equal(touching, false)
		T.equal(clear, true)
	end)
end)

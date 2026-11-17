--!strict
-- The Simulator's world arrows (#42, ADR 0017): a short trail towards the target and the push
-- direction ahead of the ball.

local T = require("../../TestKit")
local TutorialPointer = require("../../../src/client/Ui/TutorialPointer")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

-- The yaw's look vector, as CFrame.Angles(0, yaw, 0).LookVector: (-sin, 0, -cos).
local function look(yaw: number): (number, number)
	return -math.sin(yaw), -math.cos(yaw)
end

return T.suite("TutorialPointer", function(test)
	test("trail: count chevrons from the gap on, every spacing studs, facing the target", function()
		local chevrons = TutorialPointer.trail(0, 0, 100, 0, 4, 4, 3)
		T.equal(#chevrons, 4)
		for i, chevron in chevrons do
			T.isTrue(near(chevron.x, 3 + (i - 1) * 4), `x {i}`)
			T.isTrue(near(chevron.z, 0))
			local lx, lz = look(chevron.yaw)
			T.isTrue(near(lx, 1) and near(lz, 0), "points at +x")
		end
	end)

	test("trail: never past the target and nothing when already there", function()
		T.equal(#TutorialPointer.trail(0, 0, 0, 12, 10, 4, 3), 2, "3 and 7 studs; 11 is inside the gap")
		T.equal(#TutorialPointer.trail(0, 0, 0, 5, 4, 4, 3), 0)
		T.equal(#TutorialPointer.trail(0, 0, 0, 0, 4, 4, 3), 0)
		T.equal(#TutorialPointer.trail(0, 0, 0, 100, 0, 4, 3), 0)
	end)

	test("push: chevrons ahead of the ball's edge along the push direction", function()
		local chevrons = TutorialPointer.push(10, 10, 0, -2, 1.5, 3, 3)
		T.equal(#chevrons, 3)
		T.isTrue(near(chevrons[1].z, 10 - 4.5))
		T.isTrue(near(chevrons[3].z, 10 - 10.5))
		local lx, lz = look(chevrons[1].yaw)
		T.isTrue(near(lx, 0) and near(lz, -1), "points along -z")
		T.equal(#TutorialPointer.push(0, 0, 0, 0, 1, 3, 3), 0, "no direction, no arrow")
	end)
end)

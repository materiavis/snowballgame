--!strict
-- The value of the Studio switch BallRunAtObstacle (issue #97 round 1, ADR 0002 "Playtest
-- hooks"): "<name>[,<offset>[,<angle>]]". The placement itself needs Studio.

local T = require("../../../TestKit")
local RunAtObstacle = require("../../../../src/places/simulator/server/BallService/RunAtObstacle")

return T.suite("Simulator BallRunAtObstacle value (#97)", function(test)
	test("a name alone runs straight at the centre", function()
		local run = RunAtObstacle.parse("LargeObstacle")
		T.isTrue(run ~= nil)
		local value = run :: RunAtObstacle.Run
		T.equal(value.name, "LargeObstacle")
		T.equal(value.offset, 0)
		T.equal(value.angle, 0)
	end)

	test("offset and angle, spaces allowed", function()
		local run = RunAtObstacle.parse(" LargeObstacle , 1.5, -5") :: RunAtObstacle.Run
		T.equal(run.name, "LargeObstacle")
		T.equal(run.offset, 1.5)
		T.equal(run.angle, -5)
		local offsetOnly = RunAtObstacle.parse("SmallObstacle,-0.4") :: RunAtObstacle.Run
		T.equal(offsetOnly.offset, -0.4)
		T.equal(offsetOnly.angle, 0)
	end)

	test("nonsense only warns", function()
		for _, value in { "", ",1", "LargeObstacle,x", "LargeObstacle,0,90", "LargeObstacle,0,5,1", "Large,nan" } do
			local run, problem = RunAtObstacle.parse(value)
			T.equal(run, nil, value)
			T.isTrue(type(problem) == "string", value)
		end
	end)
end)

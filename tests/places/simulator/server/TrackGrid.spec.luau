--!strict
-- TrackGrid (issue #34, concept 6.2, 7.4, ADR 0003 D3): the own track never slows straight
-- rolling, retracing is track, and it regrows, on the real Config.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local TrackGrid = require("../../../../src/places/simulator/server/SurfaceService/TrackGrid")

local STEP = BallConfig.WalkSpeed * BallConfig.SampleInterval
local DT = BallConfig.SampleInterval

-- Rolls from (x, z) by (dx, dz) per step and returns how many samples were on track.
local function roll(grid: any, x: number, z: number, dx: number, dz: number, steps: number, start: number): number
	local onTrack = 0
	local rolled = math.sqrt(dx * dx + dz * dz)
	for i = 0, steps - 1 do
		if grid.advance(x + dx * i, z + dz * i, start + i * DT, rolled, true) then
			onTrack += 1
		end
	end
	return onTrack
end

return T.suite("Simulator TrackGrid (7.4)", function(test)
	test("walking straight for a whole zone is fresh snow throughout", function()
		local grid = TrackGrid.new(BallConfig :: any)
		T.equal(roll(grid, 1, 1, 0, -STEP, 450, 0), 0, "along an axis")
		local diagonal = TrackGrid.new(BallConfig :: any)
		local step = STEP / math.sqrt(2)
		T.equal(roll(diagonal, 1.3, 2.1, step, step, 450, 0), 0, "diagonally")
	end)

	test("walking straight along a cell border with jitter is fresh snow throughout", function()
		-- The real spawn path: a straight walk at x = 0, which is exactly a cell border.
		local grid = TrackGrid.new(BallConfig :: any)
		local jitter = 0.05
		local onTrack = 0
		for i = 0, 400 do
			local x = if i % 2 == 0 then jitter else -jitter
			if grid.advance(x, -i * STEP, i * DT, STEP, true) then
				onTrack += 1
			end
		end
		T.equal(onTrack, 0)
	end)

	test("the cell under the ball is never track on the way in", function()
		local grid = TrackGrid.new(BallConfig :: any)
		T.equal(grid.advance(1, 1, 0, 1, true), false, "first sample")
		T.equal(grid.advance(2, 1, 0.1, 1, true), false, "same cell")
		T.equal(grid.cellCount(), 0, "no cell is marked before the ball has left it")
	end)

	test("rolling back over the own track does not count", function()
		local grid = TrackGrid.new(BallConfig :: any)
		roll(grid, 2, 2, STEP, 0, 40, 0)
		T.isTrue(grid.cellCount() > 0, "the path was marked")
		local back = roll(grid, 2 + STEP * 40, 2, -STEP, 0, 30, 4)
		T.isTrue(back >= 25, `only {back} of 30 samples were track`)
	end)

	test("the track regrows after TrackRegrowTime", function()
		local grid = TrackGrid.new(BallConfig :: any)
		roll(grid, 2, 2, STEP, 0, 40, 0)
		local later = 4 + BallConfig.TrackRegrowTime + 1
		local again = roll(grid, 2 + STEP * 40, 2, -STEP, 0, 30, later)
		T.equal(again, 0, "all regrown")
		T.equal(grid.cellCount() > 0, true, "and the new path is marked")
	end)

	test("marked cells expire, so the grid stays small", function()
		local grid = TrackGrid.new(BallConfig :: any)
		roll(grid, 2, 2, STEP, 0, 400, 0)
		local duringWalk = grid.cellCount()
		T.isTrue(duringWalk > 0)
		grid.advance(2 + STEP * 400, 2, 40 + BallConfig.TrackRegrowTime + 1, 0, true)
		T.equal(grid.cellCount(), 0, "everything regrown")
	end)

	test("another player's track is a separate grid", function()
		local mine = TrackGrid.new(BallConfig :: any)
		local theirs = TrackGrid.new(BallConfig :: any)
		roll(mine, 2, 2, STEP, 0, 40, 0)
		T.equal(roll(theirs, 2 + STEP * 40, 2, -STEP, 0, 30, 4), 0, "their ball is untouched")
	end)

	test("Ice and Grass leave no track and are no track", function()
		local grid = TrackGrid.new(BallConfig :: any)
		for i = 0, 40 do
			T.equal(grid.advance(2 + i * STEP, 2, i * DT, STEP, false), false)
		end
		T.equal(grid.cellCount(), 0)
	end)

	test("rolling back and forth inside one cell stops counting", function()
		local grid = TrackGrid.new(BallConfig :: any)
		local spent = false
		for i = 0, 40 do
			local x = 1.5 + (if i % 2 == 0 then 0 else 1)
			if grid.advance(x, 1.5, i * DT, 1, true) then
				spent = true
			end
		end
		T.equal(spent, true, "TrackMaxRolledPerCell reached")
	end)

	test("a straight crossing never reaches the per-cell limit", function()
		-- The longest straight crossing of a cell, plus the hysteresis on both sides.
		local size = BallConfig.TrackCellSize
		local longest = size * math.sqrt(2) + BallConfig.TrackCellHysteresis * 2
		T.isTrue(longest < BallConfig.TrackMaxRolledPerCell, `{longest}`)
	end)

	test("non-finite positions are ignored", function()
		local grid = TrackGrid.new(BallConfig :: any)
		T.equal(grid.advance(0 / 0, 1, 0, 1, true), false)
		T.equal(grid.advance(math.huge, 1, 0, 1, true), false)
		T.equal(grid.cellCount(), 0)
	end)

	test("clear forgets the track", function()
		local grid = TrackGrid.new(BallConfig :: any)
		roll(grid, 2, 2, STEP, 0, 40, 0)
		grid.clear()
		T.equal(grid.cellCount(), 0)
		T.equal(roll(grid, 2 + STEP * 40, 2, -STEP, 0, 30, 4), 0, "fresh again")
	end)
end)

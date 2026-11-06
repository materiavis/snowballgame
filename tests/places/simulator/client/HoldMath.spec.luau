--!strict
-- HoldMath (issue #33 AC1, ADR 0002): the ball swings to every new walking direction around
-- the character (not through it), a big ball swings slower, and the ball keeps pace at any
-- walk speed. A small 2D simulation stands in for Roblox physics.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local E = require("../../../helpers/Economy")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")
local BallCore = require("../../../../src/places/simulator/server/BallService/BallCore")

local hold = HoldMath.new(BallConfig :: any)
local DT = 1 / 60
local ROOT_HALF_DEPTH = 0.5 -- HumanoidRootPart is 2 x 2 x 1 studs

local function length(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

-- Character position c, ball position b and velocity bv, unit hold direction h (all x/z).
type Sim = {
	cx: number,
	cz: number,
	bx: number,
	bz: number,
	bvx: number,
	bvz: number,
	hx: number,
	hz: number,
}

local function newSim(diameter: number): Sim
	local distance = hold.holdDistance(diameter)
	return { cx = 0, cz = 0, bx = 0, bz = -distance, bvx = 0, bvz = 0, hx = 0, hz = -1 }
end

-- Same order as BallController: the hold direction is the walking direction while moving,
-- and the controller reads both bodies before the physics step moves them.
local function stepSim(sim: Sim, diameter: number, dx: number, dz: number, walkSpeed: number, dt: number?)
	local step = dt or DT
	local distance = hold.holdDistance(diameter)
	local moving = length(dx, dz) > BallConfig.MoveDeadzone
	if moving then
		sim.hx, sim.hz = dx, dz
	end
	local cvx, cvz = if moving then dx * walkSpeed else 0, if moving then dz * walkSpeed else 0
	local wantX, wantZ =
		hold.desiredVelocity(sim.bx - sim.cx, sim.bz - sim.cz, sim.hx, sim.hz, distance, cvx, cvz, walkSpeed)
	local ax, az = hold.acceleration(wantX, wantZ, sim.bvx, sim.bvz)
	sim.cx += cvx * step
	sim.cz += cvz * step
	sim.bvx += ax * step
	sim.bvz += az * step
	sim.bx += sim.bvx * step
	sim.bz += sim.bvz * step
end

-- Angle between the walking direction and the direction from character to ball, degrees.
local function frontError(sim: Sim, dx: number, dz: number): number
	local ox, oz = sim.bx - sim.cx, sim.bz - sim.cz
	local l = length(ox, oz)
	local cosine = math.clamp((ox * dx + oz * dz) / l, -1, 1)
	return math.deg(math.acos(cosine))
end

return T.suite("Simulator HoldMath (7.3)", function(test)
	test("hold distance matches the server's (spawn, leash) for every size", function()
		local core = BallCore.new(BallConfig :: any, E.Config.Zones :: any, E.Zones.zoneOptics)
		for _, diameter in { 1.6, 4, 12.3, 50 } do
			T.equal(hold.holdDistance(diameter), core.holdDistance(diameter), `diameter {diameter}`)
		end
	end)

	test("a big ball swings slower: orbit speed and centripetal limits", function()
		local walkSpeed = BallConfig.WalkSpeed
		local previous = math.huge
		for _, diameter in { 1.6, 4, 20, 50 } do
			local distance = hold.holdDistance(diameter)
			local rate = hold.maxOrbitRate(distance, walkSpeed)
			T.isTrue(rate <= math.rad(BallConfig.HoldTurnRateDegrees) + 1e-9, `{diameter} turn rate`)
			T.isTrue(rate < previous, `{diameter} slower than a smaller ball`)
			previous = rate
			T.isTrue(rate * distance <= BallConfig.HoldMaxOrbitSpeedFactor * walkSpeed + 1e-9, `{diameter} speed`)
			local centripetal = rate * rate * distance
			T.isTrue(
				centripetal <= BallConfig.HoldCentripetalShare * BallConfig.HoldMaxAcceleration + 1e-9,
				`{diameter} centripetal`
			)
		end
	end)

	test("velocity and acceleration are limited", function()
		local wantX, wantZ = hold.desiredVelocity(1e6, 0, 0, -1, 3, 0, 0, BallConfig.WalkSpeed)
		T.near(length(wantX, wantZ), BallConfig.HoldMaxSpeedFactor * BallConfig.WalkSpeed, 1e-6, "far ball")
		local ax, az = hold.acceleration(1e6, 0, 0, 0)
		T.near(length(ax, az), BallConfig.HoldMaxAcceleration, 1e-6, "acceleration")
		wantX, wantZ = hold.desiredVelocity(0, -3, 0, -1, 3, 0, 0, BallConfig.WalkSpeed)
		T.near(length(wantX, wantZ), 0, 1e-9, "at the hold point and standing")
	end)

	test("a ball on top of the character is pushed out along the hold direction", function()
		local wantX, wantZ = hold.desiredVelocity(0, 0, 1, 0, 3, 0, 0, BallConfig.WalkSpeed)
		T.isTrue(wantX > 0 and math.abs(wantZ) < 1e-9)
	end)

	test("AC1: the ball stays in front through every direction change, small and big", function()
		local directions = {
			{ 0, -1 },
			{ 1, 0 },
			{ 0, 1 }, -- reversal
			{ -1, 0 },
			{ math.sqrt(0.5), math.sqrt(0.5) },
			{ 0, -1 },
		}
		-- 60 fps and a slow phone at 30 fps.
		for _, fps in { 60, 30 } do
			for _, diameter in { 1.6, 4, 20, 50 } do
				local sim = newSim(diameter)
				local label = `{fps} fps diameter {diameter}`
				for _, direction in directions do
					local dx, dz = direction[1], direction[2]
					local closest = math.huge
					for _ = 1, 4 * fps do
						stepSim(sim, diameter, dx, dz, BallConfig.WalkSpeed, 1 / fps)
						closest = math.min(closest, length(sim.bx - sim.cx, sim.bz - sim.cz))
					end
					-- Swinging around, not through: the surface stays outside the HumanoidRootPart
					-- (half depth ROOT_HALF_DEPTH). Touching the rest of the body is allowed; that is the push.
					T.isTrue(closest > diameter / 2 + ROOT_HALF_DEPTH, `{label} closest {closest}`)
					T.isTrue(frontError(sim, dx, dz) < 5, `{label} in front after turning`)
					local distance = length(sim.bx - sim.cx, sim.bz - sim.cz)
					T.near(distance, hold.holdDistance(diameter), 0.5, `{label} at hold distance`)
				end
			end
		end
	end)

	test("push speed follows walk speed: the ball keeps pace at 16, 32 and 40 studs/s", function()
		for _, walkSpeed in { BallConfig.WalkSpeed, 32, 40 } do
			local sim = newSim(4)
			for _ = 1, 3 * 60 do
				stepSim(sim, 4, 0, -1, walkSpeed)
			end
			T.near(length(sim.bvx, sim.bvz), walkSpeed, 0.1, `ball speed at walk speed {walkSpeed}`)
			T.near(length(sim.bx - sim.cx, sim.bz - sim.cz), hold.holdDistance(4), 0.1, "no lag into the character")
		end
	end)

	test("standing still, the ball comes to rest in front", function()
		local sim = newSim(4)
		for _ = 1, 60 do
			stepSim(sim, 4, 1, 0, BallConfig.WalkSpeed)
		end
		for _ = 1, 3 * 60 do
			stepSim(sim, 4, 0, 0, BallConfig.WalkSpeed)
		end
		T.near(length(sim.bvx, sim.bvz), 0, 0.05, "at rest")
		T.isTrue(frontError(sim, 1, 0) < 1, "still in front")
	end)
end)

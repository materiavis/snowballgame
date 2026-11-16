--!strict
-- Free field against main (issue #97 round 4, owner decision: without an obstacle contact the
-- hold runs main's code path). `fixtures/HoldMathMain` is BallController/HoldMath exactly as on
-- main at 2746a6d, driven like main's controller (no contact flag, plain `acceleration`); the
-- current HoldMath is driven like the current controller: contact flag false, the approach
-- limit and the rebound brake armed only within ReboundWatchTime of a contact (none here).
--
-- Model: rolling ball (5/7 of the force becomes speed), physics at 240 Hz with the force of the
-- frame, character kinematic at WalkSpeed. Every frame's hold direction, acceleration and
-- ball position must equal main's. The R5 turn time (until the ball is within 15° of the
-- walking direction and within 1 stud of the hold distance) is reported for both.

local fs = require("@lune/fs")
local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")
local HoldMathMain = require("./fixtures/HoldMathMain")

local ROLLING = 5 / 7
local WALK = BallConfig.WalkSpeed
local SETTLED_DEGREES = 15
local SETTLED_STUDS = 1
local EXACT = 1e-9

local main = HoldMathMain.new(BallConfig :: any)
local current = HoldMath.new(BallConfig :: any)

-- Walking directions on the ground plane, as W, A, S, D with the camera looking along -Z.
local W, A, S, D = { 0, -1 }, { -1, 0 }, { 0, 1 }, { 1, 0 }
local STAND = { 0, 0 }

-- Zone 1 fraction 0 (1.6) and 0.5 (2.8, hold 2.9, the R5 ball) and the zone 50 Visual Cap ball.
local DIAMETERS = { 1.6, 2.8, 50 }

type Phase = { seconds: number, move: { number } }
type Scenario = { name: string, ball: { number }, phases: { Phase } }

-- `ball` is the unit bearing of the ball at the start, at the hold distance.
local SCENARIOS: { Scenario } = {
	{ name = "W→D 90°", ball = W, phases = { { seconds = 2, move = W }, { seconds = 4, move = D } } },
	{ name = "D→W 90°", ball = D, phases = { { seconds = 2, move = D }, { seconds = 4, move = W } } },
	{ name = "W→A 90°", ball = W, phases = { { seconds = 2, move = W }, { seconds = 4, move = A } } },
	{ name = "W→S 180°", ball = W, phases = { { seconds = 2, move = W }, { seconds = 5, move = S } } },
	{ name = "S→W 180°", ball = S, phases = { { seconds = 2, move = S }, { seconds = 5, move = W } } },
	{
		name = "W↔D every 1.5 s",
		ball = W,
		phases = {
			{ seconds = 1.5, move = W },
			{ seconds = 1.5, move = D },
			{ seconds = 1.5, move = W },
			{ seconds = 1.5, move = D },
			{ seconds = 4, move = W },
		},
	},
	{
		name = "standing, ball behind, then W",
		ball = S,
		phases = { { seconds = 1, move = STAND }, { seconds = 5, move = W } },
	},
}

type Run = {
	frames: { { number } }, -- per frame: hx, hz, ax, az, bx, bz
	turnTime: number, -- after the last phase change; math.huge if never settled
}

local function run(isMain: boolean, diameter: number, scenario: Scenario, fps: number): Run
	local hold: any = if isMain then main else current
	local distance = hold.holdDistance(diameter)
	local cx, cz = 0, 0
	local bx, bz = scenario.ball[1] * distance, scenario.ball[2] * distance
	local first = scenario.phases[1].move
	local bvx, bvz = first[1] * WALK, first[2] * WALK
	local hx, hz = scenario.ball[1], scenario.ball[2]
	local frames = {}
	local contactAt: number? = nil -- never touched in free field
	local total, lastChange = 0, 0
	for index, phase in scenario.phases do
		if index == #scenario.phases then
			lastChange = total
		end
		total += phase.seconds
	end
	local turnTime = math.huge
	for frame = 1, math.floor(total * fps + 0.5) do
		local now = frame / fps
		local move = STAND
		local elapsed = 0
		for _, phase in scenario.phases do
			elapsed += phase.seconds
			if now <= elapsed + 1e-9 then
				move = phase.move
				break
			end
		end
		local dx, dz = move[1], move[2]
		local cvx, cvz = dx * WALK, dz * WALK
		local rx, rz = bx - cx, bz - cz
		local ax, az
		if isMain then
			hx, hz = hold.nextHeldDirection(hx, hz, dx, dz, rx, rz, false)
			local wantX, wantZ = hold.desiredVelocity(rx, rz, hx, hz, distance, cvx, cvz, WALK)
			ax, az = hold.acceleration(wantX, wantZ, bvx, bvz)
		else
			local armed = hold.reboundArmed(now, contactAt)
			hx, hz = hold.nextHeldDirection(hx, hz, dx, dz, rx, rz, false, false)
			local wantX, wantZ = hold.desiredVelocity(rx, rz, hx, hz, distance, cvx, cvz, WALK, armed)
			ax, az = hold.holdAcceleration(wantX, wantZ, bvx, bvz, rx, rz, cvx, cvz, distance, armed)
		end
		for _ = 1, 240 // fps do
			cx += cvx / 240
			cz += cvz / 240
			bvx += ax * ROLLING / 240
			bvz += az * ROLLING / 240
			bx += bvx / 240
			bz += bvz / 240
		end
		table.insert(frames, { hx, hz, ax, az, bx - cx, bz - cz })
		if turnTime == math.huge and now > lastChange and (dx ~= 0 or dz ~= 0) then
			local ox, oz = bx - cx, bz - cz
			local l = math.sqrt(ox * ox + oz * oz)
			local angle = math.deg(math.acos(math.clamp((ox * dx + oz * dz) / l, -1, 1)))
			if angle <= SETTLED_DEGREES and math.abs(l - distance) <= SETTLED_STUDS then
				turnTime = now - lastChange
			end
		end
	end
	return { frames = frames, turnTime = turnTime }
end

-- Largest difference of any per-frame value between two runs.
local function largestDifference(a: Run, b: Run): number
	local most = 0
	T.equal(#a.frames, #b.frames, "same frame count")
	for frame, values in a.frames do
		for index, value in values do
			most = math.max(most, math.abs(value - b.frames[frame][index]))
		end
	end
	return most
end

return T.suite("Simulator hold in free field equals main (#97 round 4, R5)", function(test)
	test("a: without a contact every frame equals main, small and large ball, 60 and 30 fps", function()
		for _, fps in { 60, 30 } do
			for _, diameter in DIAMETERS do
				for _, scenario in SCENARIOS do
					local before = run(true, diameter, scenario, fps)
					local now = run(false, diameter, scenario, fps)
					local label = `{fps} fps diameter {diameter} {scenario.name}`
					T.isTrue(largestDifference(before, now) <= EXACT, label)
					T.equal(now.turnTime, before.turnTime, `{label}: turn time`)
					T.isTrue(before.turnTime < math.huge, `{label}: main settles`)
				end
			end
		end
	end)

	test("armed only within ReboundWatchTime of the last contact", function()
		T.equal(current.reboundArmed(10, nil), false, "no contact yet")
		T.equal(current.reboundArmed(10, 10), true, "frame of the contact")
		T.equal(current.reboundArmed(10 + BallConfig.ReboundWatchTime - 0.01, 10), true, "inside the window")
		T.equal(current.reboundArmed(10 + BallConfig.ReboundWatchTime, 10), false, "window over")
	end)

	test("unarmed, the hold's acceleration and velocity are main's for any state", function()
		local distance = current.holdDistance(2.8)
		for _, state in
			{
				{ 0, -distance - 8, 0, -40, 0, 0 }, -- far out and leaving: armed this would brake
				{ 0, -distance - 1, 0, -40, 0, 0 },
				{ 3, 1, 5, -2, 16, 0 },
				{ -2.9, 0.1, -12, 30, 0, -16 },
			}
		do
			local rx, rz, bvx, bvz, cvx, cvz = table.unpack(state)
			local mx, mz = main.desiredVelocity(rx, rz, 0, -1, distance, cvx, cvz, WALK)
			local nx, nz = current.desiredVelocity(rx, rz, 0, -1, distance, cvx, cvz, WALK, false)
			T.equal(nx, mx)
			T.equal(nz, mz)
			local ax, az = main.acceleration(mx, mz, bvx, bvz)
			local hx, hz, braking = current.holdAcceleration(nx, nz, bvx, bvz, rx, rz, cvx, cvz, distance, false)
			T.equal(hx, ax)
			T.equal(hz, az)
			T.equal(braking, false)
		end
	end)

	test("d: a Placements or Recoveries change arms the hold for ReboundWatchTime (round 5)", function()
		local source = fs.readFile("src/places/simulator/client/BallController/init.luau")
		local function has(text: string): boolean
			return string.find(source, text, 1, true) ~= nil
		end
		-- One arming time for contacts, server hits and server moves, read by reboundArmed.
		T.isTrue(has("local function arm()\n\tarmedAt = os.clock()\nend"), "arm() starts the window")
		T.isTrue(has("hold.reboundArmed(now, armedAt)"), "the window is reboundArmed's")
		local move = string.match(source, "local function onServerMove%(%)(.-)\n\tend\n")
		T.isTrue(move ~= nil and string.find(move, "arm()", 1, true) ~= nil, "a server move arms")
		T.isTrue(has("GetAttributeChangedSignal(BallConfig.RecoveriesAttribute):Connect(onServerMove)"))
		T.isTrue(has("GetAttributeChangedSignal(BallConfig.PlacementsAttribute):Connect(onServerMove)"))
		-- BallHoldArmed only when it changes, not every frame.
		T.isTrue(has("if armed ~= holdArmed then"), "BallHoldArmed set on change only")
		-- Armed from the move for ReboundWatchTime: a ball 8 studs out comes back no faster than
		-- the approach limit allows, as after a contact; after the window it is main's again.
		local distance = current.holdDistance(35)
		local movedAt = 20
		for _, now in { movedAt, movedAt + BallConfig.ReboundWatchTime - 0.01, movedAt + BallConfig.ReboundWatchTime } do
			local armed = current.reboundArmed(now, movedAt)
			local _, wantZ = current.desiredVelocity(0, -distance - 8, 0, -1, distance, 0, 0, WALK, armed)
			local _, mainZ = main.desiredVelocity(0, -distance - 8, 0, -1, distance, 0, 0, WALK)
			if now < movedAt + BallConfig.ReboundWatchTime then
				T.isTrue(wantZ < mainZ - 1, `armed at {now - movedAt} s: approach limited`)
			else
				T.equal(wantZ, mainZ, "window over: main's")
			end
		end
	end)
end)

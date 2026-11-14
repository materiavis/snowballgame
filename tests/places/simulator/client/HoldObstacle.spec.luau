--!strict
-- HoldMath against an obstacle face (issue #97 round 1, ADR 0002 "After a hit"). A 2D model of
-- the by-hand LargeObstacle run of the playtest at c755723: the character walks W slightly off
-- -Z into the +Z face of LargeObstacle (x 16..24, z -34..-26), keeps pushing, then stands.
-- The character is kinematic and slides along the ball and the box; the ball rolls (5/7 of the
-- hold force becomes speed) and its contacts are inelastic. Same order as BallController: the
-- hold reads both bodies, then physics runs at 240 Hz with the force of the frame.

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local HoldMath = require("../../../../src/places/simulator/client/BallController/HoldMath")

local X0, X1, Z0, Z1 = 16, 24, -34, -26
local CHARACTER_RADIUS = 1
local ROLLING = 5 / 7
local START_Z = -10

local function length(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

-- Pushes a point out of the box grown by `radius`; returns it and the outward normal (or nil).
local function outOfBox(px: number, pz: number, radius: number): (number, number, number?, number?)
	local cx, cz = math.clamp(px, X0, X1), math.clamp(pz, Z0, Z1)
	local dx, dz = px - cx, pz - cz
	local d = length(dx, dz)
	if d >= radius then
		return px, pz, nil, nil
	end
	if d < 1e-9 then
		return px, Z1 + radius, 0, 1
	end
	return cx + dx / d * radius, cz + dz / d * radius, dx / d, dz / d
end

export type Result = {
	most: number, -- studs beyond the hold distance, within ReboundWatchTime of the first touch
	outFor: number, -- first to last frame more than ReboundSettleStuds beyond, in that window
	outAtEnd: boolean, -- still more than ReboundSettleStuds beyond at the end of the window
	ballX: number,
	ballZ: number,
	characterX: number,
	characterZ: number,
}

local function push(config: any, startX: number, angle: number, walkSeconds: number): Result
	local hold = HoldMath.new(config)
	local diameter = 4
	local radius = diameter / 2
	local distance = hold.holdDistance(diameter)
	local dx, dz = math.sin(math.rad(angle)), -math.cos(math.rad(angle))
	local cx, cz, cvx, cvz = startX, START_Z, 0, 0
	local bx, bz, bvx, bvz = startX + dx * distance, START_Z + dz * distance, 0, 0
	local touchedAt: number? = nil
	local most, firstOut, lastOut, outAtEnd = 0, nil :: number?, nil :: number?, false
	local fps = 60
	for frame = 1, (walkSeconds + 3.5) * fps do
		local now = frame / fps
		local walking = now <= walkSeconds
		local rx, rz = bx - cx, bz - cz
		local wantX, wantZ = hold.desiredVelocity(rx, rz, dx, dz, distance, cvx, cvz, config.WalkSpeed)
		local ax, az = hold.holdAcceleration(wantX, wantZ, bvx, bvz, rx, rz, cvx, cvz, distance)
		for _ = 1, 240 // fps do
			local h = 1 / 240
			local mx, mz = if walking then dx * config.WalkSpeed else 0, if walking then dz * config.WalkSpeed else 0
			local ox, oz = bx - cx, bz - cz
			local gap = length(ox, oz)
			if gap < radius + CHARACTER_RADIUS + 1e-3 and gap > 0 then
				local into = (mx * ox + mz * oz) / gap
				if into > 0 then
					mx -= into * ox / gap
					mz -= into * oz / gap
				end
			end
			local ncx, ncz = outOfBox(cx + mx * h, cz + mz * h, CHARACTER_RADIUS)
			cvx, cvz = (ncx - cx) / h, (ncz - cz) / h
			cx, cz = ncx, ncz
			bvx += ax * ROLLING * h
			bvz += az * ROLLING * h
			bx += bvx * h
			bz += bvz * h
			for _ = 1, 3 do
				local ex, ez = bx - cx, bz - cz
				local e = length(ex, ez)
				if e < radius + CHARACTER_RADIUS and e > 0 then
					local nx, nz = ex / e, ez / e
					bx, bz = cx + nx * (radius + CHARACTER_RADIUS), cz + nz * (radius + CHARACTER_RADIUS)
					local approach = (bvx - cvx) * nx + (bvz - cvz) * nz
					if approach < 0 then
						bvx -= approach * nx
						bvz -= approach * nz
					end
				end
				local px, pz, nx, nz = outOfBox(bx, bz, radius)
				if nx ~= nil and nz ~= nil then
					bx, bz = px, pz
					local normal = bvx * nx + bvz * nz
					if normal < 0 then
						bvx -= normal * nx
						bvz -= normal * nz
					end
					touchedAt = touchedAt or now
				end
			end
		end
		if touchedAt and now - touchedAt <= config.ReboundWatchTime then
			local beyond = length(bx - cx, bz - cz) - distance
			most = math.max(most, beyond)
			outAtEnd = beyond > config.ReboundSettleStuds
			if outAtEnd then
				firstOut = firstOut or now
				lastOut = now
			end
		end
	end
	return {
		most = most,
		outFor = if firstOut and lastOut then lastOut - firstOut else 0,
		outAtEnd = outAtEnd,
		ballX = bx,
		ballZ = bz,
		characterX = cx,
		characterZ = cz,
	}
end

-- The round-0 behaviour: the swing towards the walking direction at full strength at any
-- distance.
local withoutFade = table.clone(BallConfig) :: any
withoutFade.HoldBearingFadeStuds = math.huge

return T.suite("Simulator HoldMath against an obstacle face (#97)", function(test)
	test("cause: without distance before bearing the ball slides round the corner and stays there", function()
		-- Playtest at c755723, by hand: end ball (14.5, -30.4), character (19.3, -25.5), 3.85 out.
		local result = push(withoutFade, 20, -5, 2.5)
		T.isTrue(result.most > BallConfig.ReboundMaxStuds, `{result.most} studs out`)
		T.isTrue(result.ballX < X0 and result.ballZ < Z1, "ball beside the west face, past the corner")
		T.isTrue(result.characterZ > Z1, "character still in front of the +Z face")
	end)

	test("D1: off-centre and at an angle, pushing on and then standing stays inside the limit", function()
		for _, angle in { -10, -5, 0, 5, 10, 20 } do
			for _, startX in { 22, 20, 18, 16, 15, 14.5 } do
				for _, walkSeconds in { 2.5, 4 } do
					local result = push(BallConfig, startX, angle, walkSeconds)
					local label = `angle {angle} start x {startX} walk {walkSeconds} s`
					T.isTrue(result.most <= BallConfig.ReboundMaxStuds, `{label}: {result.most} studs out`)
					T.isTrue(result.outFor <= BallConfig.ReboundMaxSeconds, `{label}: out for {result.outFor} s`)
					T.isTrue(not result.outAtEnd, `{label}: still out at the end of the watch`)
				end
			end
		end
	end)

	test("a pressed ball is pushed no harder than HoldMaxAcceleration, even when it jitters (R3)", function()
		-- #94 AC8: a 35-stud ball held behind LargeObstacle, about 8 studs beyond its hold
		-- distance, pressed into the obstacle. Round 0 let a tiny outward speed unlock up to 800.
		local hold = HoldMath.new(BallConfig :: any)
		local distance = hold.holdDistance(35)
		local rz = -(distance + 8)
		local wantX, wantZ = hold.desiredVelocity(0, rz, 0, -1, distance, 0, 0, BallConfig.WalkSpeed)
		for _, jitter in { 0, 0.01, 0.5, 3 } do
			local ax, az, braking = hold.holdAcceleration(wantX, wantZ, 0, -jitter, 0, rz, 0, 0, distance)
			T.isTrue(length(ax, az) <= BallConfig.HoldMaxAcceleration + 1e-9, `jitter {jitter}: {length(ax, az)}`)
			T.equal(braking, false, `jitter {jitter}`)
		end
	end)
end)

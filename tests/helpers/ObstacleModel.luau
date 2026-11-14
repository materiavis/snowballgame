--!strict
-- 2D model of the hold against an obstacle box (issue #97, ADR 0002 "After a hit"). The
-- character is kinematic and slides along the ball and the box; the ball rolls (5/7 of the hold
-- force becomes speed) and its contacts are inelastic. Same order as BallController: the hold
-- reads both bodies, then physics runs at 240 Hz with the force of the frame.
--
-- `hold` is a HoldMath instance; `kind` "main" drives it like main before #97 (no contact flag,
-- plain `acceleration`), "new" like the current BallController.

local ObstacleModel = {}

export type Box = { x0: number, x1: number, z0: number, z1: number }

export type Setup = {
	hold: any,
	kind: string, -- "main" or "new"
	config: any,
	box: Box,
	diameter: number,
	-- Horizontal contact radius of the ball against the box: the radius for a box at least as
	-- tall as the ball's centre, less for a ball resting on a lower box's top edge.
	contactRadius: number?,
	characterX: number,
	characterZ: number,
	ballX: number,
	ballZ: number,
	walkX: number, -- unit walking direction while walking
	walkZ: number,
	walkSeconds: number,
	standSeconds: number,
	followSeconds: number?, -- hold follows the ball this long at the start (a server placement)
	friction: number?, -- Coulomb friction at the box face; 0 or nil = frictionless
	fps: number?,
}

export type Result = {
	most: number, -- studs beyond the hold distance within ReboundWatchTime of the first touch
	outFor: number, -- first to last frame more than ReboundSettleStuds beyond, in that window
	outAtEnd: boolean,
	moved: number, -- most the ball centre got from its start on the ground plane
	ballX: number,
	ballZ: number,
	characterX: number,
	characterZ: number,
}

local CHARACTER_RADIUS = 1
local ROLLING = 5 / 7

local function length(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

function ObstacleModel.run(setup: Setup): Result
	local hold, config, box = setup.hold, setup.config, setup.box
	local radius = setup.diameter / 2
	local contactRadius = setup.contactRadius or radius
	local distance = hold.holdDistance(setup.diameter)
	local fps = setup.fps or 60

	local function outOfBox(px: number, pz: number, r: number): (number, number, number?, number?)
		local cx, cz = math.clamp(px, box.x0, box.x1), math.clamp(pz, box.z0, box.z1)
		local dx, dz = px - cx, pz - cz
		local d = length(dx, dz)
		if d >= r then
			return px, pz, nil, nil
		end
		if d < 1e-9 then
			return px, box.z1 + r, 0, 1
		end
		return cx + dx / d * r, cz + dz / d * r, dx / d, dz / d
	end

	local function gapToBox(px: number, pz: number): number
		local cx, cz = math.clamp(px, box.x0, box.x1), math.clamp(pz, box.z0, box.z1)
		return length(px - cx, pz - cz) - contactRadius
	end

	local cx, cz, cvx, cvz = setup.characterX, setup.characterZ, 0, 0
	local bx, bz, bvx, bvz = setup.ballX, setup.ballZ, 0, 0
	local startX, startZ = bx, bz
	local hx, hz = setup.walkX, setup.walkZ
	local touchedAt: number? = nil
	local most, moved = 0, 0
	local firstOut: number?, lastOut: number? = nil, nil
	local outAtEnd = false
	for frame = 1, math.floor((setup.walkSeconds + setup.standSeconds) * fps) do
		local now = frame / fps
		local walking = now <= setup.walkSeconds
		local mx, mz = if walking then setup.walkX else 0, if walking then setup.walkZ else 0
		local rx, rz = bx - cx, bz - cz
		local follow = setup.followSeconds ~= nil and now < setup.followSeconds
		if setup.kind == "main" then
			hx, hz = hold.nextHeldDirection(hx, hz, mx, mz, rx, rz, follow)
		else
			local touching = gapToBox(bx, bz) <= config.HoldContactMargin
			hx, hz = hold.nextHeldDirection(hx, hz, mx, mz, rx, rz, follow, touching)
		end
		local wantX, wantZ = hold.desiredVelocity(rx, rz, hx, hz, distance, cvx, cvz, config.WalkSpeed)
		local ax, az
		if setup.kind == "main" then
			ax, az = hold.acceleration(wantX, wantZ, bvx, bvz)
		else
			ax, az = hold.holdAcceleration(wantX, wantZ, bvx, bvz, rx, rz, cvx, cvz, distance)
		end
		for _ = 1, 240 // fps do
			local h = 1 / 240
			local vx, vz = mx * config.WalkSpeed, mz * config.WalkSpeed
			local ox, oz = bx - cx, bz - cz
			local gap = length(ox, oz)
			if gap < radius + CHARACTER_RADIUS + 1e-3 and gap > 0 then
				local into = (vx * ox + vz * oz) / gap
				if into > 0 then
					vx -= into * ox / gap
					vz -= into * oz / gap
				end
			end
			local ncx, ncz = outOfBox(cx + vx * h, cz + vz * h, CHARACTER_RADIUS)
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
				local px, pz, nx, nz = outOfBox(bx, bz, contactRadius)
				if nx ~= nil and nz ~= nil then
					bx, bz = px, pz
					local normal = bvx * nx + bvz * nz
					if normal < 0 then
						bvx -= normal * nx
						bvz -= normal * nz
						-- Coulomb friction at the face: removes up to friction × the normal
						-- velocity change from the sliding speed along the face.
						local friction = setup.friction or 0
						if friction > 0 then
							local tx, tz = -nz, nx
							local slide = bvx * tx + bvz * tz
							local change = math.min(math.abs(slide), -normal * friction)
							local sign = if slide > 0 then 1 else -1
							bvx -= sign * change * tx
							bvz -= sign * change * tz
						end
					end
					touchedAt = touchedAt or now
				end
			end
		end
		moved = math.max(moved, length(bx - startX, bz - startZ))
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
		moved = moved,
		ballX = bx,
		ballZ = bz,
		characterX = cx,
		characterZ = cz,
	}
end

return table.freeze(ObstacleModel)

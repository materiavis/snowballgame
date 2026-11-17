--!strict
-- Where the chevrons of the Simulator's world hints go (concept 10.1, ADR 0017). Pure, on the
-- ground plane (x, z). The Lobby's fixed spawn-to-portal arrow is ArrowPath (ADR 0015); these
-- move with the player, so they are a short trail instead of a whole path.
--   trail: up to `count` chevrons from `gap` studs ahead of the character towards the target,
--          every `spacing` studs, never closer than `gap` to the target
--   push:  `count` chevrons ahead of the ball along the push direction (zone 1 arrival)
-- yaw turns Roblox's look direction (-z) towards the target, as in ArrowPath.

export type Chevron = { x: number, z: number, yaw: number }

local TutorialPointer = {}

local function yawOf(ux: number, uz: number): number
	return math.atan2(-ux, -uz)
end

function TutorialPointer.trail(
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	count: number,
	spacing: number,
	gap: number
): { Chevron }
	local out: { Chevron } = {}
	local dx, dz = toX - fromX, toZ - fromZ
	local length = math.sqrt(dx * dx + dz * dz)
	if count <= 0 or spacing <= 0 or length <= 2 * gap then
		return out
	end
	local ux, uz = dx / length, dz / length
	local yaw = yawOf(ux, uz)
	for i = 0, count - 1 do
		local distance = gap + i * spacing
		if distance > length - gap + 1e-9 then
			break
		end
		table.insert(out, { x = fromX + ux * distance, z = fromZ + uz * distance, yaw = yaw })
	end
	return out
end

-- Chevrons starting `radius + spacing` studs ahead of the ball centre along (dirX, dirZ).
-- No direction (zero vector): none.
function TutorialPointer.push(
	ballX: number,
	ballZ: number,
	dirX: number,
	dirZ: number,
	radius: number,
	count: number,
	spacing: number
): { Chevron }
	local out: { Chevron } = {}
	local length = math.sqrt(dirX * dirX + dirZ * dirZ)
	if length < 1e-6 or count <= 0 or spacing <= 0 then
		return out
	end
	local ux, uz = dirX / length, dirZ / length
	local yaw = yawOf(ux, uz)
	for i = 1, count do
		local distance = radius + i * spacing
		table.insert(out, { x = ballX + ux * distance, z = ballZ + uz * distance, yaw = yaw })
	end
	return out
end

return table.freeze(TutorialPointer)

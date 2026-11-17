--!strict
-- Where the chevrons of a ground arrow go (concept 7.1, 10.1; ADR 0015). Pure, on the ground
-- plane (x, z): chevrons every `spacing` studs from `gap` studs after the start to `gap` studs
-- before the target, each turned to face the target. Used by GuideArrow for the first-join arrow
-- to the Singleplayer portal; #42 reuses it for the Multiplayer arrow.

export type Chevron = { x: number, z: number, yaw: number }

local ArrowPath = {}

-- yaw is the rotation about +y (radians) that turns Roblox's look direction (-z) towards the
-- target: CFrame.Angles(0, yaw, 0).LookVector points from the chevron to the target.
function ArrowPath.chevrons(
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	spacing: number,
	gap: number
): { Chevron }
	local dx, dz = toX - fromX, toZ - fromZ
	local length = math.sqrt(dx * dx + dz * dz)
	local out: { Chevron } = {}
	if spacing <= 0 or length <= 2 * gap then
		return out
	end
	local ux, uz = dx / length, dz / length
	local yaw = math.atan2(-ux, -uz)
	local distance = gap
	while distance <= length - gap + 1e-9 do
		table.insert(out, { x = fromX + ux * distance, z = fromZ + uz * distance, yaw = yaw })
		distance += spacing
	end
	return out
end

return table.freeze(ArrowPath)

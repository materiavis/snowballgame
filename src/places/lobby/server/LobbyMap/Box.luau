--!strict
-- Box volume math for the portal walk-in volume and the VIP corner (ADR 0015). Pure: points are
-- plain numbers in the box's own space (Roblox: part.CFrame:PointToObjectSpace), so a headless
-- spec runs it. `size` is the part size {x, y, z}.

local Box = {}

-- True when the point is inside or on the surface of the box.
function Box.contains(x: number, y: number, z: number, size: { number }): boolean
	return math.abs(x) <= size[1] / 2 and math.abs(y) <= size[2] / 2 and math.abs(z) <= size[3] / 2
end

-- The nearest point `margin` studs outside the box through a side face (x or z), keeping the
-- height, for a point inside. Floors and ceilings are never used, so nobody is pushed into the
-- ground or onto the roof. A point outside is returned unchanged.
function Box.pushOut(x: number, y: number, z: number, size: { number }, margin: number): (number, number, number)
	if not Box.contains(x, y, z, size) then
		return x, y, z
	end
	local halfX, halfZ = size[1] / 2, size[3] / 2
	local toX = halfX - math.abs(x)
	local toZ = halfZ - math.abs(z)
	if toX <= toZ then
		local sign = if x < 0 then -1 else 1
		return sign * (halfX + margin), y, z
	end
	local sign = if z < 0 then -1 else 1
	return x, y, sign * (halfZ + margin)
end

return table.freeze(Box)

--!strict
-- Whether a ball touches a scale plate, from the server's own view (ADR 0012). Pure: the
-- caller turns the ball centre into the plate's object space.

export type Margins = {
	TouchMargin: number,
	ReleaseMargin: number,
}

local PlateGeometry = {}

-- Distance from a point (in the box's object space) to a box with these half sizes; 0 inside.
function PlateGeometry.boxDistance(x: number, y: number, z: number, halfX: number, halfY: number, halfZ: number): number
	local dx = math.max(math.abs(x) - halfX, 0)
	local dy = math.max(math.abs(y) - halfY, 0)
	local dz = math.max(math.abs(z) - halfZ, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Gap between the ball's surface and the box: negative when they overlap.
function PlateGeometry.gap(boxDistance: number, radius: number): number
	return boxDistance - radius
end

-- `gap` is the smallest gap to any plate (math.huge without plates). Touching and clear are
-- apart by the margins, so a ball resting at the edge does not flip between them.
function PlateGeometry.classify(gap: number, margins: Margins): (boolean, boolean)
	return gap <= margins.TouchMargin, gap > margins.ReleaseMargin
end

return table.freeze(PlateGeometry)

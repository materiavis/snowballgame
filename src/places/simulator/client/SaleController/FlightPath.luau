--!strict
-- Where the "+3.4K" label starts and lands (ADR 0012). Pure: screen points in pixels, so a
-- headless spec checks the path on real screen sizes.

export type Point = { x: number, y: number }

local FlightPath = {}

-- Centre of the label at the start: the middle of the screen at `yFraction` of its height.
function FlightPath.start(guiWidth: number, guiHeight: number, yFraction: number): Point
	return { x = guiWidth / 2, y = guiHeight * yFraction }
end

-- Centre of the Coins panel in the label's own ScreenGui. Both are AbsolutePositions; the
-- difference of the two guis' AbsolutePositions keeps it right if their insets differ.
function FlightPath.target(
	panelX: number,
	panelY: number,
	panelWidth: number,
	panelHeight: number,
	guiX: number,
	guiY: number
): Point
	return { x = panelX - guiX + panelWidth / 2, y = panelY - guiY + panelHeight / 2 }
end

-- Whether a point lies inside a rectangle (top-left x, y and size).
function FlightPath.inside(point: Point, x: number, y: number, width: number, height: number): boolean
	return point.x >= x and point.x <= x + width and point.y >= y and point.y <= y + height
end

return table.freeze(FlightPath)

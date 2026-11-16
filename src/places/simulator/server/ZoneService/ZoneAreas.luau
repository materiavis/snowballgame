--!strict
-- The shared zone-area resolver of ADR 0009 ("A shared resolver ... belongs in the first of
-- #39/#40 that needs it"), ADR 0014. Pure: ZoneMap reads Workspace.Map into plain records, this
-- module decides which zones exist, which have a start and which zone a position is in.
--
-- The ZoneIndex rules themselves (missing, invalid, other world, duplicate) stay in
-- UpgradeService/StationRules, which ZoneMap uses to fill `zone` and `problem`; this module adds
-- the ZoneStart count and the area boxes. Finds (#40) and other zone-bound features reuse it
-- through ZoneService (ZoneOfPosition, HasZone, ZoneStartCFrame).

-- Axis-aligned box in world studs around an area's parts.
export type Box = {
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	minZ: number,
	maxZ: number,
}

export type AreaRecord = {
	key: any, -- the area root (opaque here)
	name: string, -- full name, for warnings
	zone: number?, -- valid ZoneIndex, or nil (no zone, problem says why when there is one)
	problem: string?,
	starts: number, -- ZoneStart anchors inside this area
	box: Box?, -- nil when the area has no parts
}

export type Problem = { key: any, tag: string, name: string, text: string }

export type Snapshot = {
	-- Zones with a valid area, ascending (with or without a start).
	zones: { number },
	problems: { Problem },
	area: (zone: number) -> AreaRecord?,
	-- A valid area with exactly one ZoneStart: teleport target, spawn, and a barrier into it
	-- may open (ADR 0009).
	hasZone: (zone: number) -> boolean,
	-- The zone whose box holds the point; `preferred` wins where boxes overlap, else the lowest.
	zoneAt: (x: number, y: number, z: number, preferred: number?) -> number?,
}

local ZoneAreas = {}

local function contains(box: Box, x: number, y: number, z: number, margin: number): boolean
	return x >= box.minX
		and x <= box.maxX
		and z >= box.minZ
		and z <= box.maxZ
		and y >= box.minY - margin
		and y <= box.maxY + margin
end

-- `startTag` only goes into warning texts.
function ZoneAreas.snapshot(records: { AreaRecord }, options: { verticalMargin: number, startTag: string }): Snapshot
	local byZone: { [number]: AreaRecord } = {}
	local zones: { number } = {}
	local problems: { Problem } = {}

	for _, record in records do
		if record.problem ~= nil then
			table.insert(problems, { key = record.key, tag = "ZoneIndex", name = record.name, text = record.problem })
		end
		local zone = record.zone
		if zone ~= nil then
			byZone[zone] = record
			table.insert(zones, zone)
			if record.starts ~= 1 then
				table.insert(problems, {
					key = record.key,
					tag = options.startTag,
					name = record.name,
					text = `zone {zone} has {record.starts} {options.startTag} anchors (needs exactly 1), so it has no start`,
				})
			end
		end
	end
	table.sort(zones)

	local function hasZone(zone: number): boolean
		local record = byZone[zone]
		return record ~= nil and record.starts == 1
	end

	local function zoneAt(x: number, y: number, z: number, preferred: number?): number?
		local found: number? = nil
		for _, zone in zones do
			local box = byZone[zone].box
			if box ~= nil and contains(box, x, y, z, options.verticalMargin) then
				if zone == preferred then
					return zone
				end
				if found == nil then
					found = zone
				end
			end
		end
		return found
	end

	return table.freeze({
		zones = zones,
		problems = problems,
		area = function(zone: number): AreaRecord?
			return byZone[zone]
		end,
		hasZone = hasZone,
		zoneAt = zoneAt,
	})
end

-- Box around boxes; nil for none.
function ZoneAreas.union(boxes: { Box }): Box?
	local result: Box? = nil
	for _, box in boxes do
		if result == nil then
			result = table.clone(box)
		else
			local r = result :: Box
			r.minX = math.min(r.minX, box.minX)
			r.maxX = math.max(r.maxX, box.maxX)
			r.minY = math.min(r.minY, box.minY)
			r.maxY = math.max(r.maxY, box.maxY)
			r.minZ = math.min(r.minZ, box.minZ)
			r.maxZ = math.max(r.maxZ, box.maxZ)
		end
	end
	return result
end

-- World box of a part from its position, rotation matrix (the nine CFrame components) and size.
function ZoneAreas.partBox(position: { number }, rotation: { number }, size: { number }): Box
	local hx, hy, hz = size[1] / 2, size[2] / 2, size[3] / 2
	local r = rotation
	local ex = math.abs(r[1]) * hx + math.abs(r[2]) * hy + math.abs(r[3]) * hz
	local ey = math.abs(r[4]) * hx + math.abs(r[5]) * hy + math.abs(r[6]) * hz
	local ez = math.abs(r[7]) * hx + math.abs(r[8]) * hy + math.abs(r[9]) * hz
	return {
		minX = position[1] - ex,
		maxX = position[1] + ex,
		minY = position[2] - ey,
		maxY = position[2] + ey,
		minZ = position[3] - ez,
		maxZ = position[3] + ez,
	}
end

return table.freeze(ZoneAreas)

--!strict
-- What the Simulator's progress bar and zone name show (concept 10.2, #90; ADR 0008). Pure: the
-- size and the zone come only from the server's player attributes (`BallSizeMetres`,
-- `BallZone`, ADR 0002), and the zone maximum from the shared zone formula for that zone. A
-- missing or invalid value shows a placeholder, never an error.

export type Zones = {
	isZone: (zone: any) -> boolean,
	maxSize: (zone: number) -> number,
}

local ZoneProgress = {}

local function isSize(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value ~= math.huge
end

-- Share of the zone maximum, 0..1, or nil when the size or the zone is unknown.
function ZoneProgress.fraction(metres: any, zone: any, zones: Zones): number?
	if not isSize(metres) or not zones.isZone(zone) then
		return nil
	end
	local ok, maximum = pcall(zones.maxSize, zone)
	if not ok or not isSize(maximum) or maximum <= 0 then
		return nil
	end
	return math.clamp(metres / maximum, 0, 1)
end

-- "1.2 m / 2 m" with `format` = NumberFormat.size, or Text.ProgressPlaceholder.
function ZoneProgress.barText(metres: any, zone: any, zones: Zones, format: (number) -> string, ui: any): string
	if ZoneProgress.fraction(metres, zone, zones) == nil then
		return ui.Text.ProgressPlaceholder
	end
	local okSize, sizeText = pcall(format, metres)
	local okMax, maxText = pcall(function()
		return format(zones.maxSize(zone))
	end)
	if not okSize or not okMax then
		return ui.Text.ProgressPlaceholder
	end
	return `{sizeText}{ui.Text.ProgressSeparator}{maxText}`
end

-- The zone's name from `names` (Config.Zones.Names), or Text.ZoneNamePlaceholder.
function ZoneProgress.zoneName(zone: any, names: { string }, zones: Zones, ui: any): string
	if zones.isZone(zone) then
		local name = names[zone]
		if type(name) == "string" and name ~= "" then
			return name
		end
	end
	return ui.Text.ZoneNamePlaceholder
end

return table.freeze(ZoneProgress)

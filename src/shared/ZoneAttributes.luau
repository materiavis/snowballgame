--!strict
-- Player attribute names ZoneService writes (#39, ADR 0014) and the text form of the unlocked
-- zones. Pure, shared by the server (writer) and the client (reader).
--
-- ZonesUnlocked is written on every server while the profile is loaded (the client contract for
-- the zone teleport list and barrier passability). The others are Studio-only diagnostics.

local ZoneAttributes = {
	UNLOCKED = "ZonesUnlocked", -- "1,2,3": unlocked zones, ascending
	-- Studio at PlaceId 0 only.
	CURRENT = "ZoneCurrent", -- zone the server counts the player in
	LAST_EVENT = "ZoneLastEvent", -- last unlock, teleport, return or reset as text
	LAST_REFUSAL = "ZoneLastRefusal", -- last refused unlock, teleport or entry as text
	REFUSALS = "ZoneRefusals", -- count of refusals
	LAST_SAVE = "ZoneLastSave", -- result of the immediate save after the last unlock
}

-- "1,2,3" from a list of zones (sorted, duplicates dropped). Empty list: "".
function ZoneAttributes.encode(zones: { number }): string
	local sorted = table.clone(zones)
	table.sort(sorted)
	local parts: { string } = {}
	local last: number? = nil
	for _, zone in sorted do
		if zone ~= last then
			table.insert(parts, tostring(zone))
			last = zone
		end
	end
	return table.concat(parts, ",")
end

-- The zones of an attribute value, ascending, or nil if the value is not a valid list. Every
-- entry must pass `isZone` (Formulas.Zones.isZone); one bad entry makes the whole value invalid,
-- so a client never shows a partial or invented list.
function ZoneAttributes.decode(value: any, isZone: (value: any) -> boolean): { number }?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	local zones: { number } = {}
	for piece in string.gmatch(value .. ",", "([^,]*),") do
		local zone = tonumber(piece)
		if zone == nil or not isZone(zone) or string.match(piece, "^%d+$") == nil then
			return nil
		end
		table.insert(zones, zone)
	end
	table.sort(zones)
	return zones
end

return table.freeze(ZoneAttributes)

--!strict
-- Where following pets stand and how they catch up (concept 7.9 Spielraum "Laufverhalten",
-- ADR 0013). Pure: numbers in, numbers out, so the formation and the smoothing are tested
-- headless. Offsets are in the character's frame: x to the right, z backwards (Roblox's
-- CFrame.new(x, 0, z) with +z behind a character that looks along -z).

export type FollowConfig = {
	BackDistance: number,
	Spacing: number,
	RowDepth: number,
	PerRow: number,
	Sharpness: number,
	SnapDistance: number,
}

local PetFormation = {}

-- Pets side by side behind the character, centred, PerRow per row; later rows stand further back.
function PetFormation.offset(index: number, count: number, config: FollowConfig): (number, number)
	local perRow = math.max(1, config.PerRow)
	local row = (index - 1) // perRow
	local inRow = math.min(perRow, count - row * perRow)
	local position = (index - 1) % perRow
	local x = (position - (inRow - 1) / 2) * config.Spacing
	local z = config.BackDistance + row * config.RowDepth
	return x, z
end

-- Share of the remaining gap a pet closes in `dt` seconds (exponential smoothing), so the motion
-- looks the same at any frame rate and at the lower update rate of foreign pets.
function PetFormation.alpha(dt: number, sharpness: number): number
	if dt <= 0 then
		return 0
	end
	return 1 - math.exp(-sharpness * dt)
end

-- True when a pet is so far from its place (teleport, respawn) that it should jump there.
function PetFormation.shouldSnap(distance: number, config: FollowConfig): boolean
	return distance > config.SnapDistance
end

-- Height of a pet's centre: on the ground under the character plus half its size.
-- Ground = root centre - half the root height - HipHeight (how Humanoids stand).
function PetFormation.height(rootY: number, rootHalfHeight: number, hipHeight: number, size: number): number
	return rootY - rootHalfHeight - hipHeight + size / 2
end

return table.freeze(PetFormation)

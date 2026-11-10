--!strict
-- One player's snow track (concept 6.2, 7.4, ADR 0003 D3): a logical grid that never edits
-- shared geometry, so a foreign track slows nobody. Pure, so `lune run tests` loads it.
--
-- A cell becomes track when the ball's contact point has left it, never while it is on it,
-- so the cell under the ball still counts and walking straight is fresh snow all the way.
-- Only the contact line is track, not the ball's width: a ball touches the ground at one
-- point, and marking the width of a 50-stud ball would mark the snow in front of it too.

export type TrackConfig = {
	TrackCellSize: number,
	TrackCellHysteresis: number,
	TrackRegrowTime: number,
	TrackMaxRolledPerCell: number,
}

export type TrackGrid = {
	advance: (x: number, z: number, now: number, rolled: number, onSnow: boolean) -> boolean,
	cellCount: () -> number,
	clear: () -> (),
}

-- Cell coordinates are packed into one number key: an allocation-free table key that stays
-- exact far beyond any map (doubles hold 53 bits).
local KEY_OFFSET = 2 ^ 24
local KEY_STRIDE = 2 ^ 25
-- Removing from the front of an array is linear, so finished entries are dropped in batches.
local COMPACT_AFTER = 128

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local TrackGridModule = {}

function TrackGridModule.new(config: TrackConfig): TrackGrid
	local size = config.TrackCellSize
	local marked: { [number]: number } = {} -- key -> time the snow is back
	local markedCount = 0
	-- Entries in order of expiry. A cell marked again leaves a stale entry behind.
	local queueKeys: { number } = {}
	local queueTimes: { number } = {}
	local queueHead = 1

	local currentKey: number? = nil
	local currentX, currentZ = 0, 0
	local rolledInCell = 0
	local lastRolledAt: number? = nil -- last time snow was rolled in the current cell

	local function keyOf(cellX: number, cellZ: number): number
		return (cellX + KEY_OFFSET) * KEY_STRIDE + (cellZ + KEY_OFFSET)
	end

	local function expire(now: number)
		while queueTimes[queueHead] ~= nil and queueTimes[queueHead] <= now do
			local key, time = queueKeys[queueHead], queueTimes[queueHead]
			if marked[key] == time then
				marked[key] = nil
				markedCount -= 1
			end
			queueHead += 1
		end
		if queueHead > COMPACT_AFTER then
			local remaining = #queueKeys - queueHead + 1
			table.move(queueKeys, queueHead, #queueKeys, 1)
			table.move(queueTimes, queueHead, #queueTimes, 1)
			for index = #queueKeys, remaining + 1, -1 do
				queueKeys[index] = nil
				queueTimes[index] = nil
			end
			queueHead = 1
		end
	end

	-- The snow regrows from the last time it was rolled, not from when the ball left: a ball
	-- that stands in a cell for a minute has given that cell time to regrow. Entries stay in
	-- order of expiry because a later cell cannot have been rolled before an earlier one.
	local function mark(key: number, rolledAt: number, now: number)
		local time = rolledAt + config.TrackRegrowTime
		if time <= now then
			return
		end
		if marked[key] == nil then
			markedCount += 1
		end
		marked[key] = time
		table.insert(queueKeys, key)
		table.insert(queueTimes, time)
	end

	local function enter(cellX: number, cellZ: number)
		currentKey = keyOf(cellX, cellZ)
		currentX, currentZ = cellX, cellZ
		rolledInCell = 0
		lastRolledAt = nil
	end

	local function outsideCurrentBy(x: number, z: number): number
		local minX, minZ = currentX * size, currentZ * size
		return math.max(minX - x, x - (minX + size), minZ - z, z - (minZ + size))
	end

	-- Call once per sample with the contact point, the studs rolled since the last sample and
	-- whether the ground here is snow. Returns whether this sample is on the own track.
	local function advance(x: number, z: number, now: number, rolled: number, onSnow: boolean): boolean
		if not isFinite(x) or not isFinite(z) or not isFinite(now) or not isFinite(rolled) then
			return false
		end
		expire(now)

		local cellX, cellZ = math.floor(x / size), math.floor(z / size)
		if currentKey == nil then
			enter(cellX, cellZ)
		elseif (cellX ~= currentX or cellZ ~= currentZ) and outsideCurrentBy(x, z) > config.TrackCellHysteresis then
			if lastRolledAt ~= nil then
				mark(currentKey :: number, lastRolledAt :: number, now)
			end
			enter(cellX, cellZ)
		end

		if not onSnow then
			return false
		end
		if rolled > 0 then
			rolledInCell += rolled
			lastRolledAt = now
		end
		local backAt = marked[currentKey :: number]
		-- Without the second test, rolling back and forth inside one cell would grow forever.
		return (backAt ~= nil and backAt > now) or rolledInCell > config.TrackMaxRolledPerCell
	end

	local function cellCount(): number
		return markedCount
	end

	local function clear()
		table.clear(marked)
		table.clear(queueKeys)
		table.clear(queueTimes)
		markedCount = 0
		queueHead = 1
		currentKey = nil
	end

	return table.freeze({
		advance = advance,
		cellCount = cellCount,
		clear = clear,
	})
end

return table.freeze(TrackGridModule)

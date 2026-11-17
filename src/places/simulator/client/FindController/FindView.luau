--!strict
-- Pure display rules for finds (concept 7.7, 8.5, ADR 0016): which update the client accepts,
-- where a find sticks in the ball and how large it is drawn. Config is passed in, so specs run
-- it headless with the real Config.Finds and Config.Net.

local FindView = {}

local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
-- Stride through the spiral, coprime to any MaxInBall that is not a multiple of 7, so the first
-- finds already spread round the ball instead of piling up at its top.
local STRIDE = 7

export type Vector = { x: number, y: number, z: number }

-- True for a find id of the catalogue.
function FindView.isFind(findsConfig: any, findId: any): boolean
	return type(findId) == "string" and findsConfig.Items[findId] ~= nil
end

-- True for a slot the server can send (whole number 1..MaxSlot).
function FindView.isSlot(netFinds: any, slot: any): boolean
	return type(slot) == "number" and slot == slot and slot >= 1 and slot <= netFinds.MaxSlot and slot % 1 == 0
end

-- Unit direction from the ball centre of the `index`-th find in the ball (1-based): points on a
-- Fibonacci sphere of `count` places, visited with a stride. Deterministic.
function FindView.inBallDirection(index: number, count: number): Vector
	local place = ((index - 1) * STRIDE) % count
	local y = 1 - (place + 0.5) * 2 / count
	local ring = math.sqrt(math.max(0, 1 - y * y))
	local angle = place * GOLDEN_ANGLE
	return { x = math.cos(angle) * ring, y = y, z = math.sin(angle) * ring }
end

-- How many of `count` finds in the ball are drawn.
function FindView.shownInBall(visual: any, count: number): number
	return math.clamp(count, 0, visual.MaxInBall)
end

-- Size in studs of a find stuck in a ball of `diameter` studs.
function FindView.inBallSize(visual: any, diameter: number): number
	return math.clamp(diameter * visual.InBallShare, visual.InBallMinStuds, visual.InBallMaxStuds)
end

-- Billboard height for a disc of `size` with the stars or crown under it.
function FindView.billboardHeight(visual: any, size: number): number
	return size / (1 - visual.SymbolHeightShare)
end

return table.freeze(FindView)

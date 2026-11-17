--!strict
-- ZoneAreas (#39, ADR 0009 "Zone number" and "ZoneStart", ADR 0014): which zones exist and have
-- a start, which zone a position is in, and the part boxes. The ZoneIndex rules themselves are
-- StationRules (StationRules.spec); the records here are what ZoneMap builds from them.

local T = require("../../../TestKit")
local ZoneAreas = require("../../../../src/places/simulator/server/ZoneService/ZoneAreas")

local OPTIONS = { verticalMargin = 30, startTag = "ZoneStart" }

local function box(minX: number, maxX: number): ZoneAreas.Box
	return { minX = minX, maxX = maxX, minY = -2, maxY = 16, minZ = -40, maxZ = 40 }
end

local function record(zone: number?, starts: number, b: ZoneAreas.Box?, problem: string?): ZoneAreas.AreaRecord
	return { key = { zone = zone }, name = `Map.Area{zone}`, zone = zone, problem = problem, starts = starts, box = b }
end

return T.suite("ZoneAreas (#39)", function(test)
	test("a zone needs exactly one ZoneStart; 0 or 2 warn and leave it without a start", function()
		local snap = ZoneAreas.snapshot({
			record(1, 1, box(0, 120)),
			record(2, 0, box(120, 240)),
			record(3, 2, box(240, 360)),
		}, OPTIONS)
		T.equal(table.concat(snap.zones, ","), "1,2,3")
		T.equal(snap.hasZone(1), true)
		T.equal(snap.hasZone(2), false)
		T.equal(snap.hasZone(3), false)
		T.equal(snap.hasZone(4), false)
		T.equal(#snap.problems, 2)
		T.isTrue(string.find(snap.problems[1].text, "has 0 ZoneStart", 1, true) ~= nil, snap.problems[1].text)
		T.isTrue(string.find(snap.problems[2].text, "has 2 ZoneStart", 1, true) ~= nil, snap.problems[2].text)
	end)

	test("areas without a zone are not zones; their ZoneIndex problem is reported", function()
		local snap = ZoneAreas.snapshot({
			record(nil, 0, nil), -- the Placeholder: no ZoneIndex, no problem
			record(nil, 1, box(0, 10), "zone area X shares ZoneIndex 1 with Y"),
		}, OPTIONS)
		T.equal(#snap.zones, 0)
		T.equal(#snap.problems, 1)
		T.equal(snap.problems[1].tag, "ZoneIndex")
	end)

	test("zoneAt: the box holds the point, with a vertical margin", function()
		local snap = ZoneAreas.snapshot({ record(1, 1, box(0, 120)), record(2, 1, box(120, 240)) }, OPTIONS)
		T.equal(snap.zoneAt(10, 3, 0, nil), 1)
		T.equal(snap.zoneAt(200, 3, 0, nil), 2)
		T.equal(snap.zoneAt(200, 45, 0, nil), 2, "within the margin above")
		T.equal(snap.zoneAt(200, 47, 0, nil), nil, "above the margin")
		T.equal(snap.zoneAt(200, -40, 0, nil), nil, "fallen below the map")
		T.equal(snap.zoneAt(200, 3, 41, nil), nil, "off the side")
		T.equal(snap.zoneAt(-1, 3, 0, nil), nil)
	end)

	test("zoneAt: where boxes overlap the current zone wins, else the lowest", function()
		local snap = ZoneAreas.snapshot({ record(1, 1, box(0, 125)), record(2, 1, box(115, 240)) }, OPTIONS)
		T.equal(snap.zoneAt(120, 3, 0, 2), 2)
		T.equal(snap.zoneAt(120, 3, 0, 1), 1)
		T.equal(snap.zoneAt(120, 3, 0, nil), 1)
		T.equal(snap.zoneAt(120, 3, 0, 5), 1)
	end)

	test("partBox and union: rotated parts give their world box", function()
		local straight = ZoneAreas.partBox({ 0, 0, 0 }, { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, { 4, 2, 6 })
		T.equal(straight.minX, -2)
		T.equal(straight.maxZ, 3)
		-- 90 degrees about Y: X and Z extents swap.
		local turned = ZoneAreas.partBox({ 10, 0, 0 }, { 0, 0, 1, 0, 1, 0, -1, 0, 0 }, { 4, 2, 6 })
		T.equal(turned.minX, 7)
		T.equal(turned.maxX, 13)
		T.equal(turned.minZ, -2)
		local all = ZoneAreas.union({ straight, turned }) :: ZoneAreas.Box
		T.equal(all.minX, -2)
		T.equal(all.maxX, 13)
		T.equal(ZoneAreas.union({}), nil)
	end)
end)

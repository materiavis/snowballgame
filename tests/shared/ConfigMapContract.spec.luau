--!strict
-- The zone contract check reads its tag names only from Config.Map.ZoneContract, so it knows no
-- game names. This spec keeps those lists equal to the names game code binds to (ADR 0009 and
-- ADR 0002), so a renamed tag cannot drift away from the check.

local T = require("../TestKit")
local Map = require("../../src/shared/Config/Map")
local Ball = require("../../src/shared/Config/Ball")

local Contract = Map.ZoneContract

local function asSet(list: { string }): { [string]: boolean }
	local set = {}
	for _, name in list do
		set[name] = true
	end
	return set
end

local function sameSet(actual: { string }, expected: { string }, label: string)
	local a, e = asSet(actual), asSet(expected)
	for name in e do
		T.isTrue(a[name], `{label}: missing {name}`)
	end
	for name in a do
		T.isTrue(e[name], `{label}: unknown {name}`)
	end
end

return T.suite("src/shared/Config/Map ZoneContract names", function(test)
	test("anchor tags match game code", function()
		sameSet(Contract.AnchorTags, { Map.Tags.ZoneStart, Map.Tags.FindPoint, Ball.ScaleAnchorTag }, "AnchorTags")
		T.equal(Contract.StartTag, Map.Tags.ZoneStart)
	end)

	test("part tags match game code", function()
		local expected = { Map.Tags.ScalePlate, Ball.ObstacleTag }
		for _, surface in Ball.Surfaces do
			table.insert(expected, surface)
		end
		sameSet(Contract.PartTags, expected, "PartTags")
	end)

	test("station tags match game code", function()
		-- ADR 0009 names WorldGate; no code binds it yet, so it is not in Map.Tags.
		sameSet(
			Contract.StationTags,
			{ Map.Tags.UpgradeStand, Map.Tags.EggStation, Map.Tags.Barrier, "WorldGate" },
			"StationTags"
		)
	end)

	test("knock-over names match game code", function()
		T.equal(Contract.KnockOverTag, Ball.ObstacleTag)
		T.equal(Contract.KnockOverAttribute, Ball.KnockOverSizeAttribute)
	end)
end)

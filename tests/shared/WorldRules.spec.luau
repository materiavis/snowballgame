--!strict
-- Keeps Config.WorldRules (the game's names for the general world-builder and zone check)
-- equal to the names game code binds to (ADR 0009, ADR 0002). This test belongs to the game,
-- not to the world-builder: it is the one place where both meet.

local T = require("../TestKit")
local Rules = require("../../src/shared/Config/WorldRules")
local Map = require("../../src/shared/Config/Map")
local Ball = require("../../src/shared/Config/Ball")

local function expectKinds(expected: { [string]: string })
	for tag, kind in expected do
		T.equal(Rules.TagKinds[tag], kind, `TagKinds.{tag}`)
	end
	for tag in Rules.TagKinds do
		T.isTrue(expected[tag] ~= nil, `TagKinds.{tag} is not a tag game code uses`)
	end
end

return T.suite("src/shared/Config/WorldRules", function(test)
	test("names match the map config", function()
		T.equal(Rules.ZoneNumberAttribute, Map.ZoneIndexAttribute)
		T.equal(Rules.StartTag, Map.Tags.ZoneStart)
		T.equal(Rules.GroupStreamingMode, Map.StationStreamingMode)
	end)

	test("tag kinds match ADR 0009", function()
		expectKinds({
			[Map.Tags.ZoneStart] = "Point",
			[Map.Tags.FindPoint] = "Point",
			[Ball.ScaleAnchorTag] = "Point",
			[Map.Tags.ScalePlate] = "Part",
			[Ball.ObstacleTag] = "Part",
			[Map.Tags.UpgradeStand] = "Group",
			[Map.Tags.EggStation] = "Group",
			[Map.Tags.Barrier] = "Group",
			-- ADR 0009 names WorldGate; no code binds it yet, so it is not in Map.Tags.
			WorldGate = "Group",
		})
	end)

	test("positive attributes match game code", function()
		T.equal(#Rules.PositiveAttributes, 1)
		T.equal(Rules.PositiveAttributes[1].Tag, Ball.ObstacleTag)
		T.equal(Rules.PositiveAttributes[1].Attribute, Ball.KnockOverSizeAttribute)
	end)

	test("limits are well formed", function()
		local function checkLimits(counts: { [string]: any }?, shares: { any }?, label: string)
			for tag, range in counts or {} do
				T.isTrue(Rules.TagKinds[tag] ~= nil, `{label} Counts.{tag} is a known tag`)
				T.isTrue(range.Min == nil or range.Max == nil or range.Min <= range.Max, `{label} Counts.{tag}`)
			end
			for i, share in shares or {} do
				T.isTrue(Rules.TagKinds[share.Tag] ~= nil, `{label} Shares[{i}] tag is known`)
				T.isTrue((share.Min or 0) >= 0 and (share.Max or 1) <= 1, `{label} Shares[{i}] in 0..1`)
			end
		end
		checkLimits(Rules.Counts, Rules.Shares, "")
		for world, limits in Rules.Worlds do
			checkLimits(limits.Counts, limits.Shares, `Worlds.{world}`)
		end
	end)
end)

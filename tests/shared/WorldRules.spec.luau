--!strict
-- Config.WorldRules (the game's names for the general world-builder and zone check) is well
-- formed: every tag the rules mention has a known kind, and every limit makes sense.

local T = require("../TestKit")
local Rules = require("../../src/shared/Config/WorldRules")

local KINDS = { Point = true, Part = true, Group = true }

return T.suite("src/shared/Config/WorldRules", function(test)
	test("the basics the builder needs are set", function()
		T.equal(type(Rules.ZoneNumberAttribute), "string")
		T.equal(type(Rules.StartTag), "string")
		T.equal(type(Rules.BoundsFolder), "string")
		T.isTrue(Rules.MaxZoneNumber >= 1 and Rules.MaxZoneNumber % 1 == 0, "MaxZoneNumber")
	end)

	test("every tag kind is Point, Part or Group", function()
		for tag, kind in Rules.TagKinds do
			T.isTrue(KINDS[kind] ~= nil, `TagKinds.{tag} = {kind}`)
		end
	end)

	test("limits name tags with a kind and stay in range", function()
		local function checkLimits(counts: { [string]: any }?, shares: { any }?, label: string)
			for tag, range in counts or {} do
				T.isTrue(Rules.TagKinds[tag] ~= nil or tag == Rules.StartTag, `{label} Counts.{tag} has a kind`)
				T.isTrue(range.Min == nil or range.Max == nil or range.Min <= range.Max, `{label} Counts.{tag}`)
			end
			for i, share in shares or {} do
				T.isTrue(Rules.TagKinds[share.Tag] ~= nil, `{label} Shares[{i}] tag has a kind`)
				T.isTrue((share.Min or 0) >= 0 and (share.Max or 1) <= 1, `{label} Shares[{i}] in 0..1`)
			end
		end
		checkLimits(Rules.Counts, Rules.Shares, "")
		for world, limits in Rules.Worlds do
			checkLimits(limits.Counts, limits.Shares, `Worlds.{world}`)
		end
		for i, entry in Rules.PositiveAttributes do
			T.isTrue(Rules.TagKinds[entry.Tag] ~= nil, `PositiveAttributes[{i}] tag has a kind`)
		end
	end)
end)

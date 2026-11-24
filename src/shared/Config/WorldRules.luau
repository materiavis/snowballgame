--!strict
-- World rules: the one file where THIS game tells the general world-builder and the zone check
-- its own names. The world-builder agent, tools/world/build.luau and the zone check know no
-- game; everything game-specific they need comes from here. Another game copies the generic
-- parts and writes its own version of this file.
--
-- Values follow ADR 0009 (map contract). tests/shared/WorldRules.spec.luau keeps them equal to
-- the names game code binds to, so a renamed tag cannot drift away from the check.

export type Range = { Min: number?, Max: number? }
-- "Point": Attachment or BasePart. "Part": BasePart. "Group": Model with PrimaryPart and the
-- streaming mode GroupStreamingMode.
export type Kind = "Point" | "Part" | "Group"
export type Share = { Tag: string, Attribute: string, Min: number?, Max: number? }
export type Limits = { Counts: { [string]: Range }?, Shares: { Share }? }

return table.freeze({
	-- Zone files: world/<world>/ZoneNN.rbxmx, NN = zone number with two digits.
	ZoneFilePattern = "^Zone(%d%d)%.rbxmx$",
	-- Attribute on the zone root with its number, 1..MaxZoneNumber.
	ZoneNumberAttribute = "ZoneIndex",
	MaxZoneNumber = 50,
	-- Folder in every zone root with the invisible walls at the zone edge.
	BoundsFolder = "Bounds",
	-- Tag of the zone start; every zone has exactly one. The builder puts it on an Attachment.
	StartTag = "ZoneStart",
	-- Which kind of object each tag must sit on. Tags not listed here are not checked.
	TagKinds = table.freeze({
		ZoneStart = "Point",
		FindPoint = "Point",
		ScaleAnchor = "Point",
		ScalePlate = "Part",
		Obstacle = "Part",
		UpgradeStand = "Group",
		EggStation = "Group",
		Barrier = "Group",
		WorldGate = "Group",
	}) :: { [string]: Kind },
	GroupStreamingMode = "Atomic",
	-- Attributes that must be a positive number when they are set on an object with the tag.
	PositiveAttributes = table.freeze({
		table.freeze({ Tag = "Obstacle", Attribute = "KnockOverSize" }),
	}) :: { { Tag: string, Attribute: string } },
	-- Optional limits for every world, counted per object (a Model counts once).
	-- Counts: [<tag>] = { Min, Max }. Shares: the share of <tag> objects that carry a positive
	-- <attribute>, between 0 and 1. Empty on purpose: the team fills them from the approved spec.
	Counts = table.freeze({}) :: { [string]: Range },
	Shares = table.freeze({}) :: { Share },
	-- Per-world limits replace the ones above: Worlds["<folder name>"] = { Counts = ..., Shares = ... }.
	Worlds = table.freeze({}) :: { [string]: Limits },
})

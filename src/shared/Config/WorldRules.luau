--!strict
-- World rules: the one file where THIS game tells the general world-builder and the zone check
-- its own names. The world-builder agent, tools/world/build.luau and the zone check know no
-- game; everything game-specific they need comes from here. Another game copies the generic
-- parts and writes its own version of this file.
--
-- Kept to what the builder itself needs. Tag kinds, positive attributes and limits are added
-- only when a world task asks for them, with the line from the issue as a comment.

export type Range = { Min: number?, Max: number? }
-- "Point": Attachment or BasePart. "Part": BasePart. "Group": Model with PrimaryPart and the
-- streaming mode GroupStreamingMode.
export type Kind = "Point" | "Part" | "Group"
export type Share = { Tag: string, Attribute: string, Min: number?, Max: number? }
export type Limits = { Counts: { [string]: Range }?, Shares: { Share }? }

return table.freeze({
	-- Zone files: world/<world>/ZoneNN.rbxmx, NN = zone number with two digits.
	ZoneFilePattern = "^Zone(%d%d)%.rbxmx$",
	-- Attribute on the zone root with its number, 1..MaxZoneNumber. The game reads it to know
	-- which zone a player is in.
	ZoneNumberAttribute = "ZoneIndex",
	MaxZoneNumber = 50,
	-- Folder in every zone root with the invisible walls at the zone edge.
	BoundsFolder = "Bounds",
	-- Tag of the zone start; every zone has exactly one. The game puts arriving players there.
	StartTag = "ZoneStart",
	-- Which kind of object a tag must sit on: [<tag>] = "Point" | "Part" | "Group".
	-- Tags not listed here are not checked. Empty until a world task asks for a tag.
	TagKinds = table.freeze({}) :: { [string]: Kind },
	-- Streaming mode every "Group" must use.
	GroupStreamingMode = "Atomic",
	-- Attributes that must be a positive number when set: { Tag = "<tag>", Attribute = "<name>" }.
	PositiveAttributes = table.freeze({}) :: { { Tag: string, Attribute: string } },
	-- Optional limits for every world, counted per object (a Model counts once).
	-- Counts: [<tag>] = { Min, Max }. Shares: the share of <tag> objects that carry a positive
	-- <attribute>, between 0 and 1.
	Counts = table.freeze({}) :: { [string]: Range },
	Shares = table.freeze({}) :: { Share },
	-- Per-world limits replace the ones above: Worlds["<folder name>"] = { Counts = ..., Shares = ... }.
	Worlds = table.freeze({}) :: { [string]: Limits },
	-- Kit sizes, not used by the builder or the zone check. Share of a zone's visual ball maximum
	-- (concept 7.3) at which a small obstacle becomes knock-over-able: the asset-builder sets
	-- KnockOverSize = KnockOverShare x D(zone) / Config.Ball.KnockOverSizeRatio. PLAYTEST TUNING,
	-- provisional (docs/kits/welt1-plan.md, F4). Must stay above 0.4, the ball's start share.
	KnockOverShare = 0.7,
})

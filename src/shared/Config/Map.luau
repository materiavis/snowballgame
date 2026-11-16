--!strict
-- Map contract names used by code (ADR 0009 "Where the names live in code"). Pure data.
-- Names, not design values: no price, odds or zone name lives in the map. Created by the first
-- feature that binds a map station (#36, the upgrade stand); #38-#41 add their tags here.

local Map = {
	-- Code binds only to tagged instances below Workspace[FolderName].
	FolderName = "Map",
	-- Number attribute on a zone area root (a direct child of Workspace.Map).
	ZoneIndexAttribute = "ZoneIndex",
	-- Optional Attachment inside a station that marks where its label goes.
	LabelAnchorName = "LabelAnchor",
	-- Enum.ModelStreamingMode name every station Model must use.
	StationStreamingMode = "Atomic",

	Tags = table.freeze({
		UpgradeStand = "UpgradeStand",
		-- Zones and barriers (#39, ADR 0009, ADR 0014).
		ZoneStart = "ZoneStart",
		Barrier = "Barrier",
	}),

	-- The prompt the server puts on an upgrade stand's PrimaryPart. The client opens the Upgrades
	-- window when a prompt with PromptTag triggers. Spielraum (concept 7.8: look of the stand).
	UpgradeStand = table.freeze({
		PromptName = "UpgradeStandPrompt",
		PromptTag = "UpgradeStandPrompt",
		MaxActivationDistance = 10, -- studs
		HoldDuration = 0, -- seconds
		KeyboardKeyCode = "E", -- Enum.KeyCode name
		GamepadKeyCode = "ButtonX", -- Enum.KeyCode name
	}),

	-- Barrier stations (#39, ADR 0014). The server writes the attributes on every bound barrier
	-- Model (builders never set them): the zone it ends and whether it can open in this Place
	-- (map and Config.Zones.HighestOpenZone). The client shows labels and prompts only for
	-- barriers with these attributes. ClosedReasonAttribute is Studio-only diagnostics.
	Barrier = table.freeze({
		ZoneAttribute = "BarrierZone",
		CanOpenAttribute = "BarrierCanOpen",
		ClosedReasonAttribute = "BarrierClosedReason",
		-- Tag of the client-made prompt, so the walk-in and the prompt share one path.
		PromptTag = "BarrierPrompt",
		-- A client puts the parts of a barrier it has unlocked into this group locally, so its
		-- own character and ball pass and everybody else's view is unchanged (collision group
		-- changes do not replicate). The server registers it next to the ball groups.
		OpenCollisionGroup = "OpenBarrier",
		OpenCollisionRules = table.freeze({
			table.freeze({ "OpenBarrier", "OwnCharacter", false }),
			table.freeze({ "OpenBarrier", "OwnBall", false }),
			table.freeze({ "OpenBarrier", "Balls", true }),
			table.freeze({ "OpenBarrier", "OtherCharacters", true }),
			table.freeze({ "OpenBarrier", "Default", true }),
		}),
	}),

	-- Which zone area a character stands in (ZoneService, ADR 0014). Technical, not design values.
	ZoneAreas = table.freeze({
		CheckInterval = 0.25, -- seconds between server checks per player
		-- An area's box is the box around its parts; a character counts as inside when it is
		-- within this many studs above or below it (the floor is thin, the root stands above it).
		VerticalMargin = 30,
		-- After the server returned a player to a zone start, the old position may still arrive
		-- for a moment; checks pause this many seconds.
		ReturnGrace = 1,
		-- The character's root is placed this many studs above a ZoneStart anchor.
		StartHeight = 3,
		-- Longest wait for the area around a teleport target to stream in for the player (s).
		StreamTimeout = 5,
	}),

	-- Studio-only test zones (ZoneTestGeometry, ADR 0014): areas ZoneTest01..ZoneTest06 in a row
	-- along +X beyond the +X edge of the Placeholder ground, so falling off the side is a real
	-- fall into the void. Test fixtures, not design values.
	ZoneTest = table.freeze({
		AreaPrefix = "ZoneTest",
		Count = 6,
		Origin = table.freeze({ 1100, 0, 0 }), -- start edge of zone 1, top of the floor
		Length = 120, -- studs along +X per zone
		Width = 80,
		FloorThickness = 2,
		StartInset = 12, -- ZoneStart distance from the start edge of its zone
		BarrierThickness = 2,
		BarrierHeight = 16,
		BarrierTransparency = 0.5,
		LabelHeight = 3, -- LabelAnchor above the top of the gate
	}),

	-- Studio-only test geometry for the stand (UpgradeStandTestGeometry, ADR 0010): how far in
	-- front of the target character the test stand stands, and its part size. Not design values.
	StandTest = table.freeze({
		Distance = 12, -- studs
		PartSize = table.freeze({ 4, 4, 4 }), -- studs
		Spacing = 8, -- studs between the test stands
	}),
}

return table.freeze(Map)

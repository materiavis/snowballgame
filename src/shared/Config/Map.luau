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

	-- Studio-only test geometry for the stand (UpgradeStandTestGeometry, ADR 0010): how far in
	-- front of the target character the test stand stands, and its part size. Not design values.
	StandTest = table.freeze({
		Distance = 12, -- studs
		PartSize = table.freeze({ 4, 4, 4 }), -- studs
		Spacing = 8, -- studs between the test stands
	}),
}

return table.freeze(Map)

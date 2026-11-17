--!strict
-- Look and feel of the barrier label, the unlock window and the zone teleport window (#39,
-- ADR 0014). Spielraum (concept 7.6: look of the barrier). Texts are in Config.Ui.Text, window
-- sizes and the 44 px floor in Config.Ui (ADR 0008). Studs and seconds unless named otherwise.

local ZoneUi = {
	-- The character "walks into" a barrier when its root is inside the barrier's box grown by
	-- this many studs (the blocking parts stop it at the face). Checked on the client every
	-- WalkInInterval seconds; leaving the grown box arms it again.
	WalkInMargin = 3,
	WalkInInterval = 0.1,

	-- Label above a barrier ("Zone 2 · 320"): a BillboardGui at the barrier's LabelAnchor, else
	-- this far above the top of its PrimaryPart. Size in studs, so it reads like a sign.
	Label = table.freeze({
		WidthStuds = 14,
		HeightStuds = 3,
		OffsetStuds = 3,
		MaxDistance = 200,
		TextSize = 32,
	}),

	-- Rows of both windows are ButtonBase high (scaled, at least Config.Ui.MinTouchTarget).
	UnlockWindow = table.freeze({
		-- The question takes this many button heights above the Yes and No buttons.
		QuestionRows = 2,
		Gap = 8,
	}),
	TeleportWindow = table.freeze({
		Gap = 6,
		ScrollBarThickness = 6,
	}),
}

return table.freeze(ZoneUi)

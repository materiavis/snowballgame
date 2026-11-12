--!strict
-- HUD and window tuning (concept 3.2, 10.2, 10.3; ADR 0008). Pure data, so the layout math in
-- src/client/Ui can be tested headless with these exact values.
-- Fixed by the concept: buttons at least 44 px, windows at most two thirds of the screen on
-- phones, nothing over the joystick or the ball, close via X / menu key / B, Upgrades on U or
-- D-pad right (7.8). Everything else here is Spielraum (sizes, colours, fonts, texts).
-- Pixels are ScreenGui pixels (points on phones). Colours are RGB 0-255 and fonts are
-- Enum.Font names, because Color3 and Enum do not exist outside Roblox.

local Ui = {
	-- Concept 3.2 / 10.2: the hard floor for every button, after any scaling.
	MinTouchTarget = 44,
	-- Concept 10.2: a window never exceeds this share of the screen width or height.
	WindowMaxFraction = 2 / 3,

	-- A "phone" is a touch screen whose short side is below this. iPhone SE landscape is about
	-- 667 x 375 points, large phones about 932 x 430, the smallest iPad about 1024 x 744.
	PhoneMaxShortSide = 500,

	-- Sizes below are for a short side of ScaleReferenceShortSide and scale with the screen,
	-- clamped to [MinScale, MaxScale]. MinTouchTarget is applied after scaling.
	ScaleReferenceShortSide = 400,
	MinScale = 0.85,
	MaxScale = 1.25,

	Margin = 10, -- screen edge to HUD
	Gap = 8, -- between HUD elements
	ButtonBase = 52, -- square button side and HUD row height before the 44 px floor
	CornerRadius = 8,
	StrokeThickness = 2,

	Hud = {
		CoinsWidth = 150,
		BallSizeWidth = 130,
		MenuButtonWidth = 120,
		HintWidth = 300,
		HintHeight = 48,
		HintMinHeight = 20, -- the hint shrinks to this on short screens to stay off the ball
		-- Caption ("Coins") share of a HUD panel's height; the value takes the rest.
		CaptionFraction = 0.35,
	},

	Window = {
		MaxWidth = 520,
		MaxHeight = 420,
		-- If avoiding the ball would make a phone window narrower than this, the window keeps
		-- this width and may overlap the ball area (ADR 0008 open question).
		MinWidth = 200,
		MinHeight = 160,
		Padding = 12,
	},

	-- Upgrades window rows (#36, ADR 0010). Spielraum (concept 7.8: look of the menu). A row is two
	-- lines of ButtonBase height (scaled, at least MinTouchTarget): name and level over the effect
	-- on the left, the price over the buy button on the right.
	UpgradesWindow = {
		RowGap = 8,
		-- Share of the row width for the price and buy column.
		BuyColumnFraction = 0.35,
		BuyMinWidth = 80,
		ScrollBarThickness = 6,
		-- How long the "Need … more" message stays after a tap on a greyed buy button.
		MissingMessageSeconds = 2,
		-- Share of a row's info column for the name; the level takes the rest.
		NameFraction = 0.65,
	},

	-- How each upgrade reads in the window (Spielraum). The effect is shown as
	-- Prefix .. value .. Unit, with value = effect * Scale at Decimals decimals.
	UpgradeRows = {
		growth = table.freeze({ Name = "Growth", Prefix = "", Unit = " s to MAX", Scale = 1, Decimals = 2 }),
		walkSpeed = table.freeze({ Name = "Walk speed", Prefix = "", Unit = " studs/s", Scale = 1, Decimals = 2 }),
		magnet = table.freeze({ Name = "Magnet", Prefix = "", Unit = " studs", Scale = 1, Decimals = 1 }),
		sellValue = table.freeze({ Name = "Sell value", Prefix = "×", Unit = "", Scale = 1, Decimals = 2 }),
		stability = table.freeze({
			Name = "Stability",
			Prefix = "",
			Unit = " % lost per hit",
			Scale = 100,
			Decimals = 2,
		}),
	},

	-- Areas that HUD and windows keep clear on touch screens (concept 10.2). Each side is
	-- max(fraction of the screen, minimum px). They approximate Roblox's default touch
	-- controls and the third-person ball; the playtest on a small phone checks them.
	ClearZones = {
		-- Bottom-left, where the dynamic thumbstick appears.
		Joystick = table.freeze({ WidthFraction = 0.4, HeightFraction = 0.5, MinWidth = 200, MinHeight = 130 }),
		-- Bottom-right, Roblox's jump button. Not named by the concept; kept clear so an open
		-- window does not block jumping.
		Jump = table.freeze({ SizeFraction = 0.3, MinSize = 110 }),
		-- Around the screen centre, where the third-person camera shows the ball.
		Ball = table.freeze({ CentreX = 0.5, CentreY = 0.5, WidthFraction = 0.2, HeightFraction = 0.3 }),
	},

	TextSize = {
		Caption = 14,
		Value = 24,
		Button = 20,
		Title = 24,
		Body = 18,
		Hint = 16,
	},

	Fonts = {
		Regular = "GothamMedium",
		Bold = "GothamBold",
	},

	-- Materiavis direction: red, dark grey, white.
	Colours = {
		Brand = table.freeze({ 151, 0, 7 }),
		Surface = table.freeze({ 34, 34, 38 }),
		SurfaceRaised = table.freeze({ 56, 56, 62 }),
		Text = table.freeze({ 255, 255, 255 }),
		TextMuted = table.freeze({ 200, 200, 205 }),
		-- The ball-size caption while the ball is at MAX (same yellow as the MAX arrow, 7.4).
		Max = table.freeze({ 255, 210, 60 }),
	},
	PanelTransparency = 0.15,

	-- Enum.KeyCode names. Keyboard and gamepad keys of one window share a list.
	Keybinds = {
		-- Closes the top window. Bound only while a window is open, so B is never taken from
		-- gameplay otherwise.
		CloseTop = table.freeze({ "ButtonB" }),
		Upgrades = table.freeze({
			Toggle = table.freeze({ "U" }), -- opens, or closes when open
			Open = table.freeze({ "DPadRight" }), -- opens; passes through while a GUI is selected
		}),
	},
	-- ContextActionService priority (Enum.ContextActionPriority.High), above default gameplay binds.
	ActionPriority = 3000,

	DisplayOrder = {
		Hud = 10,
	},
	ZIndex = {
		Hud = 1,
		Window = 10,
	},

	-- English source strings; Roblox automatic translation picks up the static ones. Numbers are
	-- separate labels so a translated caption never contains a changing value.
	Text = {
		Coins = "Coins",
		BallSize = "Size",
		Upgrades = "Upgrades",
		-- Upgrades window (#36). The values next to them are separate, unlocalised labels.
		UpgradeBuy = "Buy",
		-- Shown briefly when a greyed buy button is tapped; {amount} is the missing price, e.g.
		-- "Need 1.2K more" (owner decision 2026-11-12, like the barrier in 7.6).
		UpgradeNeedMore = "Need {amount} more",
		-- Locked upgrades (Config.Upgrades.Locked, owner decision 2026-11-12).
		UpgradeComingSoon = "Coming soon",
		UpgradeMax = "MAX",
		-- Between the effect now and after the next level.
		UpgradeArrow = " → ",
		-- Upgrade stand prompt (ProximityPrompt texts).
		UpgradeStandAction = "Upgrades",
		UpgradeStandObject = "Upgrade stand",
		Close = "X",
		-- Shown instead of a balance while the profile is not loaded (owner decision on #35).
		Missing = "–",
		-- Ball size before the server has published one (BallSizeMetres, #34).
		BallSizePlaceholder = "– m",
		-- Interim: replaces the "Size" caption while the ball is at MAX. Where and how long MAX!
		-- shows for good is an open owner question (follow-up issue to #35).
		BallSizeMax = "MAX!",
		LoadFailed = "Your progress could not be loaded. Trying again…",
	},

	-- DataLoadStatus (ADR 0006) -> key in Text for the load hint. A status not listed shows no
	-- hint. Balances show Text.Missing for every status except "Loaded".
	LoadHints = {
		Failed = "LoadFailed",
	},
}

for _, key in
	{
		"Hud",
		"Window",
		"UpgradesWindow",
		"UpgradeRows",
		"ClearZones",
		"TextSize",
		"Fonts",
		"Colours",
		"Keybinds",
		"DisplayOrder",
		"ZIndex",
		"Text",
		"LoadHints",
	}
do
	table.freeze((Ui :: any)[key])
end

return table.freeze(Ui)

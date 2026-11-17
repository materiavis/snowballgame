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
		-- The load hint sits in the top row (#90: under the ball size is now the progress bar),
		-- right of the ball size in the Simulator and centred in the Lobby, one row high.
		HintWidth = 300,
		-- Caption ("Coins") share of a HUD panel's height; the value takes the rest.
		CaptionFraction = 0.35,
		-- Progress bar under the ball size (#90): same width as the ball size field. The zone
		-- name under it shrinks down to ZoneNameMinHeight on short screens to stay off the ball.
		ProgressGap = 3,
		ProgressBarHeight = 16,
		ZoneNameHeight = 16,
		ZoneNameMinHeight = 10,
	},

	-- Left-edge menu buttons (concept 10.2, #90), top to bottom. A button other than Upgrades is
	-- hidden until its feature registers it (owner decision 2026-11-16): Pets with #41, Zonen-
	-- Teleport with #39, Lobby with the Travel follow-up. Each id has a Text entry (label) and a
	-- Keybinds entry. When the column would reach the joystick, the buttons wrap into columns.
	LeftButtons = { "Upgrades", "Pets", "ZoneTeleport", "Lobby" },

	-- Short centre pop-ups (concept 10.2, #90). A pop-up shows for DurationSeconds; pop-ups that
	-- arrive meanwhile wait, at most MaxQueued of them (the oldest waiting one is dropped).
	-- Width and height shrink (down to the minimums) to stay off the joystick and the HUD.
	Popup = {
		Width = 260,
		Height = 48,
		MinWidth = 90,
		MinHeight = 28,
		DurationSeconds = 1.5,
		MaxQueued = 3,
		-- How many numbers a pop-up may carry and how large they may be: Config.Net.Popup.
	},
	-- Text keys (in Text) the server may send in a pop-up. Features add theirs here ("MAX!",
	-- "+3.4K" and "New Pet!" come with #109, #38 and #41). {1} and {2} are numbers, formatted
	-- with NumberFormat.number (K, M, B ...).
	PopupTexts = {
		"PopupTest",
		"PopupTestNumber",
		"PromptTriggered",
		"PlaceholderButton",
		-- Pets and eggs (#41).
		"PetHatched",
		"PetInventoryFull",
		-- Zones and barriers (#39, ADR 0014).
		"BarrierNeedMore",
		"ZoneUnlocked",
		"ZoneTeleportWait",
		"ZoneTeleportFailed",
		-- Group chest (#37, ADR 0015).
		"GroupChestOpened",
		"GroupChestAlreadyOpened",
		"GroupChestJoinGroup",
		"GroupChestNoGroup",
		"GroupChestTryLater",
		"GroupChestNotReady",
	},

	-- ProximityPrompt presets for Prompts.create (#90). Roblox's default prompt style shows the
	-- key of the last used device by itself (concept 3.2 glossary). A preset overrides Default.
	-- ActionText and ObjectText are keys in Text; key codes are Enum.KeyCode names. Spielraum:
	-- features add their presets (#37, #38, #39, #41).
	Prompts = {
		Default = table.freeze({
			KeyboardKeyCode = "E",
			GamepadKeyCode = "ButtonX",
			HoldDuration = 0, -- seconds
			MaxActivationDistance = 10, -- studs
			RequiresLineOfSight = false,
		}),
		-- Studio-only placeholder prompt (HudTestPrompt, ADR 0008 "Studio switches").
		Placeholder = table.freeze({
			ActionText = "PromptTestAction",
			ObjectText = "PromptTestObject",
		}),
		-- Egg station (#41, ADR 0013): E / tap hatches one egg (concept 7.9 "Schlüpfen").
		EggStation = table.freeze({
			ActionText = "EggStationAction",
			ObjectText = "EggStationObject",
		}),
		-- Barrier (#39, ADR 0014): the client puts it on a barrier this player can buy; it opens
		-- the same unlock window (or missing amount) as walking into the barrier.
		Barrier = table.freeze({
			ActionText = "BarrierPromptAction",
			ObjectText = "BarrierPromptObject",
		}),
		-- Lobby group chest (#37, ADR 0015). The server checks the reach again on trigger.
		GroupChest = table.freeze({
			ActionText = "GroupChestAction",
			ObjectText = "GroupChestObject",
		}),
	},

	-- Studio-only test geometry (HudTestPrompt): the placeholder part stands this far in front of
	-- and above the first SpawnLocation (studs, in the spawn's frame). Not design values.
	StudioTest = {
		PromptOffset = table.freeze({ 0, 2, -10 }),
		PromptPartSize = table.freeze({ 2, 2, 2 }),
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

	-- Pets window (#41, ADR 0013). Spielraum (concept 7.9: look of the inventory). Pets show as a
	-- grid of cells: name, rarity (stars and name in the rarity colour), bonus, and an equip
	-- button. A cell is three lines; the button line keeps the 44 px floor.
	PetsWindow = table.freeze({
		CellMinWidth = 150, -- before scaling; the grid uses as many columns as fit
		CellGap = 8,
		LineHeight = 22, -- name and rarity lines, before scaling
		ScrollBarThickness = 6,
		-- "×1.15": at most this many decimals, trailing zeros dropped (concept writes ×1.1, ×4.4).
		MultiplierDecimals = 2,
	}),

	-- Egg station label (#41, ADR 0013): a BillboardGui at the station's LabelAnchor (or above its
	-- PrimaryPart) with the price and the chances of every pet (concept 7.9, 8.5: chances always
	-- visible before the purchase). Sizes in studs, so the label belongs to the station.
	EggStationLabel = table.freeze({
		SizeStuds = table.freeze({ 9, 8 }),
		-- Above the PrimaryPart when the station has no LabelAnchor.
		OffsetStuds = table.freeze({ 0, 6, 0 }),
		MaxDistance = 80,
		-- Lines: title, price, one per pet, the message line.
		TitleTextSize = 28,
		LineTextSize = 22,
		-- How long "Need … more" stays after a tap without enough coins.
		MissingMessageSeconds = 2,
	}),

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
		Popup = 28,
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
		-- Progress bar to the zone maximum (#90): track and fill. The bar also carries its value
		-- as text, so the fill colour is never the only cue.
		ProgressTrack = table.freeze({ 20, 20, 24 }),
		ProgressFill = table.freeze({ 90, 140, 200 }),
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
		-- Left-edge buttons of #90 (owner decision 2026-11-16). Bound only while registered.
		Pets = table.freeze({
			Toggle = table.freeze({ "P" }),
			Open = table.freeze({ "DPadLeft" }),
		}),
		ZoneTeleport = table.freeze({
			Toggle = table.freeze({ "T" }),
			Open = table.freeze({ "DPadUp" }),
		}),
		-- No D-pad: all four directions are taken. Controllers reach it by GUI selection.
		Lobby = table.freeze({
			Toggle = table.freeze({ "L" }),
			Open = table.freeze({}),
		}),
	},
	-- ContextActionService priority (Enum.ContextActionPriority.High), above default gameplay binds.
	ActionPriority = 3000,

	DisplayOrder = {
		Hud = 10,
		-- Pets window (#41): its own ScreenGui, above the HUD so the window covers HUD parts.
		PetsHud = 11,
	},
	ZIndex = {
		Hud = 1,
		Window = 10,
		-- Above the HUD, below windows: a pop-up never hides an open window's buttons.
		Popup = 5,
	},

	-- English source strings; Roblox automatic translation picks up the static ones. Numbers are
	-- separate labels so a translated caption never contains a changing value.
	Text = {
		Coins = "Coins",
		BallSize = "Size",
		Upgrades = "Upgrades",
		-- Left-edge buttons (#90). "Teleport" is the zone teleport (concept: Zonen-Teleport).
		Pets = "Pets",
		ZoneTeleport = "Teleport",
		Lobby = "Lobby",
		-- Lobby HUD (#90).
		SnowCoins = "Snow Coins",
		-- Progress bar and zone name (#90): shown while the zone or the size is unknown.
		ZoneNamePlaceholder = "–",
		ProgressPlaceholder = "–",
		-- Between the ball size and the zone maximum on the progress bar ("1.2 m / 2 m").
		ProgressSeparator = " / ",
		-- Pop-ups (#90). Test texts for the Studio switches; features add their own.
		PopupTest = "Test popup",
		PopupTestNumber = "+{1}",
		PromptTriggered = "Prompt used!",
		PlaceholderButton = "Coming soon",
		-- Studio placeholder prompt (HudTestPrompt).
		PromptTestAction = "Test",
		PromptTestObject = "Placeholder prompt",
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
		-- Pets and eggs (#41, ADR 0013). Templates with {…} are filled into unlocalised labels.
		PetHatched = "New Pet!",
		PetInventoryFull = "Inventory full!",
		EggStationAction = "Hatch",
		EggStationObject = "Egg Station",
		EggPrice = "{price} Coins",
		EggComingSoon = "Coming soon",
		-- Like the upgrade decision of 2026-11-12: the missing price, rounded up ("Need 1.2K more").
		EggNeedMore = "Need {amount} more",
		EggHatching = "Hatching…",
		PetsEquip = "Equip",
		PetsUnequip = "Unequip",
		PetsSlotsFull = "Slots full",
		PetsEmpty = "No pets yet. Hatch an egg at the Egg Station!",
		PetsSlots = "Equipped {used}/{total}",
		PetsMultiplier = "Coins ×{value}",
		PetsCount = "{count}/{size} pets",
		-- A pet's bonus as a multiplier, "×1.1" (concept 7.9 writes it this way).
		PetsBonus = "×{value}",
		-- Zones and barriers (#39, ADR 0014, concept 7.6). {zone}, {price} and {name} are filled
		-- by the client (value labels, AutoLocalize off); {1} in pop-ups by PopupController.
		BarrierLabel = "Zone {zone} · {price}",
		-- A barrier that cannot open in this Place yet (map or Config.Zones.HighestOpenZone).
		BarrierClosed = "Zone {zone} · Coming soon",
		BarrierPromptAction = "Unlock",
		BarrierPromptObject = "Barrier",
		ZoneUnlockTitle = "Unlock zone",
		ZoneUnlockQuestion = "Unlock Zone {zone} for {price}?",
		ZoneUnlockYes = "Yes",
		ZoneUnlockNo = "No",
		ZoneTeleportTitle = "Zone teleport",
		ZoneTeleportRow = "Zone {zone} · {name}",
		-- Pop-ups. BarrierNeedMore is the missing amount, rounded up like a price (ADR 0014).
		BarrierNeedMore = "Need {1} more",
		ZoneUnlocked = "Zone {1} unlocked!",
		ZoneTeleportWait = "Teleport ready in {1} s",
		ZoneTeleportFailed = "Teleport failed",
		-- Lobby portals (#37, ADR 0015). Mode names from the concept's English names appendix.
		-- {count} is the number of players in the mode, formatted with NumberFormat.number.
		PortalSingleplayer = "Singleplayer",
		PortalMultiplayer = "Multiplayer",
		PortalPlayers = "{count} playing",
		PortalClosed = "Coming soon",
		PortalLocked = "Your progress is still loading…",
		PortalTravelling = "Teleporting…",
		-- Group chest prompt and pop-ups (#37). {1} Coins, {2} Snow Coins.
		GroupChestAction = "Open",
		GroupChestObject = "Group chest",
		GroupChestOpened = "+{1} Coins  +{2} Snow Coins",
		GroupChestAlreadyOpened = "Already opened",
		GroupChestJoinGroup = "Join the Materiavis group",
		GroupChestNoGroup = "Opens soon",
		GroupChestTryLater = "Try again in a moment",
		GroupChestNotReady = "Still loading…",
		-- News board (#37). {title} is Config.Lobby.News.LastUpdate, {time} the countdown.
		NewsTitle = "News",
		NewsLastUpdate = "Latest update: {title}",
		NewsNextUpdate = "Next update in {time}",
		NewsNextUpdateSoon = "Next update: coming soon",
		-- VIP corner sign (#37).
		VipCornerSign = "VIP",
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
		"LeftButtons",
		"Popup",
		"PopupTexts",
		"Prompts",
		"StudioTest",
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

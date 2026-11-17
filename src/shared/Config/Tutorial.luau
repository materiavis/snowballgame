--!strict
-- Onboarding hints of the first five minutes (concept 10.1, #42, ADR 0017). Pure data.
-- Fix (10.1): no text tutorial, only arrows and symbols; new players start in the Lobby.
-- Spielraum (10.1): the look of the hints, so every size, colour and timing here is
-- Development's call unless a comment names the concept.
--
-- A hint is shown once and disappears after its action. Its state is the schema v1 profile
-- table `tutorial` (ADR 0003, DataService/Schema): `hints[id] = true` for every id below except
-- the Multiplayer arrow, which is `tutorial.seenMultiArrow`. The first-join arrow to the
-- Singleplayer portal is `tutorial.seenSingleArrow` and stays with PortalService (ADR 0015).
-- Distances in studs, times in seconds, colours RGB 0-255.

local Tutorial = {
	-- Timeline order of concept 10.1. Within a channel the first eligible hint wins; a hint
	-- that is showing keeps its channel until it is done (no hint appears twice).
	Order = {
		"LobbyMove", -- 0:00 animated hand on joystick / W A S D
		"LobbyMultiArrow", -- next Lobby visit: once an arrow to the Multiplayer portal (🟦)
		"ZoneMove", -- 0:20 arrival in zone 1: hand shows the controls, arrow in push direction
		"MaxScale", -- 1:00 first MAX: arrow to the scale
		"UpgradesButton", -- 1:20 first sale: arrow to the Upgrades button
		"EggStation", -- 2:20 enough Coins for egg 1: arrow to the egg station
		"BarrierPulse", -- 4:20 enough Coins for the first barrier: the barrier pulses
	},

	-- Place: PlaceInfo.Role where the hint exists. Channel: what it draws on; hints of different
	-- channels may show together (the hand and a world arrow), one per channel. Requires: hints
	-- that must be done first (the controls come before everything else of a Place).
	Hints = {
		LobbyMove = table.freeze({ Place = "Lobby", Channel = "Controls", Requires = table.freeze({}) }),
		LobbyMultiArrow = table.freeze({
			Place = "Lobby",
			Channel = "World",
			Requires = table.freeze({ "LobbyMove" }),
		}),
		ZoneMove = table.freeze({ Place = "Simulator", Channel = "Controls", Requires = table.freeze({}) }),
		MaxScale = table.freeze({ Place = "Simulator", Channel = "World", Requires = table.freeze({ "ZoneMove" }) }),
		-- MaxScale is done by the first sale, so "after the first sale" is "MaxScale done".
		UpgradesButton = table.freeze({
			Place = "Simulator",
			Channel = "Screen",
			Requires = table.freeze({ "MaxScale" }),
		}),
		EggStation = table.freeze({ Place = "Simulator", Channel = "World", Requires = table.freeze({ "ZoneMove" }) }),
		BarrierPulse = table.freeze({
			Place = "Simulator",
			Channel = "Pulse",
			Requires = table.freeze({ "ZoneMove" }),
		}),
	},

	-- The only hints a client may report as done (TutorialHintDone remote): the server cannot see
	-- a window open. The server accepts a report only while that hint is showing for the player.
	ClientReportable = { "UpgradesButton" },

	-- The hint stored as tutorial.seenMultiArrow instead of hints[id].
	MultiArrowHint = "LobbyMultiArrow",

	-- Server check loop.
	CheckInterval = 0.25,
	-- "The player moves": horizontal distance walked while the controls hint shows. Steps longer
	-- than MaxStepPerCheck in one check are teleports or respawns and do not count.
	MoveDoneDistance = 6,
	MaxStepPerCheck = 12,
	-- "Reaches the station" / "walks into the barrier": distance from the character root to the
	-- station Model's bounding box.
	EggReachDistance = 8,
	BarrierReachDistance = 4,
	-- Concept 10.1: "das erste Ei" and "die erste Barriere".
	EggIndex = 1,
	BarrierZone = 1,
	-- A world target is republished when it moved more than this.
	TargetEpsilon = 0.5,

	-- Client visuals (Spielraum 10.1). The hand is a stylised finger made of Frames until real art
	-- exists (see ADR 0017 "Open points").
	Display = table.freeze({
		GuiName = "TutorialHints",
		-- Above the HUD (10) and the sale label (11), below nothing that takes input: every hint
		-- object is non-interactive, so taps and clicks pass through to the HUD and the joystick.
		DisplayOrder = 12,
		ColourRGB = table.freeze({ 255, 210, 60 }), -- the MAX / guide yellow
		KeyColourRGB = table.freeze({ 34, 34, 38 }),
		KeyTextRGB = table.freeze({ 255, 255, 255 }),
		HandRGB = table.freeze({ 255, 255, 255 }),
		PulseSeconds = 1.2,
		-- Controls glyph: key caps (W A S D) or a stick, in px before scaling.
		KeySize = 44,
		KeyGap = 6,
		StickSize = 96,
		StickKnobFraction = 0.45,
		FingerSize = table.freeze({ 22, 40 }), -- width, height
		-- Distance of the glyph block from the bottom edge on keyboard and gamepad screens.
		BottomMargin = 24,
		-- Arrow beside the Upgrades button: length and thickness of its arms, gap to the button.
		PointerArmLength = 22,
		PointerArmThickness = 6,
		PointerGap = 8,
		RingThickness = 4,
		-- World arrows (simulator): a trail of chevrons from the character towards the target.
		TrailCount = 4,
		TrailSpacing = 4,
		TrailStartGap = 3,
		TrailHeight = 0.3, -- above the character's feet
		ArmSize = table.freeze({ 2.2, 0.2, 0.5 }), -- length, thickness, width
		-- Push direction at the zone 1 arrival: chevrons ahead of the ball.
		PushCount = 3,
		PushSpacing = 3,
		-- A pulsing pillar over a world target, so it can be seen from far away.
		BeaconSize = table.freeze({ 1.5, 30, 1.5 }),
		-- How often the world arrows follow the character.
		WorldRefreshSeconds = 0.1,
		-- How often the client checks whether the Upgrades window is open.
		WindowCheckSeconds = 0.2,
	}),

	-- Symbols of the controls hint per input device (concept 3.2: the glyph of the last used
	-- device). Key caps carry key names, which are symbols, not sentences; they are not
	-- translated. Keyboard: Roblox's default movement keys, the first one is tapped.
	Glyphs = table.freeze({
		MoveKeys = table.freeze({ "W", "A", "S", "D" }),
		-- The gamepad stick that moves the character, drawn as a stick with this cap.
		MoveStickCap = "L",
	}),

	-- Studio-only stand-ins for the egg station and the barrier (TutorialTestStations, ADR 0017),
	-- until the real ones of #41 and #39 exist. Offsets in the target character's frame.
	Test = table.freeze({
		AreaName = "TutorialTest",
		EggOffset = table.freeze({ 30, 0, -20 }),
		BarrierOffset = table.freeze({ -30, 0, -20 }),
		EggSize = table.freeze({ 6, 6, 6 }),
		BarrierSize = table.freeze({ 20, 12, 2 }),
		EggRGB = table.freeze({ 240, 200, 120 }),
		BarrierRGB = table.freeze({ 120, 170, 230 }),
	}),
}

table.freeze(Tutorial.Order)
table.freeze(Tutorial.Hints)
table.freeze(Tutorial.ClientReportable)

return table.freeze(Tutorial)

--!strict
-- Eggs that can be bought and how hatching runs (concept 7.9, 6.5, ADR 0013). Prices, chances and
-- the egg zones stay in Config.Pets and Formulas.Pets; the pets of an egg are the Config.Pets
-- Catalogue entries with that egg number.

local Eggs = {
	-- Eggs on sale, by egg number. An egg station of an egg that is not listed here shows
	-- "Coming soon" and sells nothing. Egg 2 joins with #103. The name is what the station shows
	-- (Spielraum: the concept names eggs only by number).
	Available = table.freeze({
		[1] = table.freeze({ Name = "Egg 1" }),
	}),

	-- Concept 6.5 "Ei doppelt angetippt: nur ein Kauf". After a hatch the server refuses the next
	-- hatch of that player for this long (Spielraum: about one hatch animation).
	HatchCooldownSeconds = 1,

	-- A hatch request counts only while the character stands this far beyond the prompt's
	-- MaxActivationDistance from the station at most (network delay, the character moving away).
	StationReachTolerance = 6, -- studs

	-- Hatch reveal at the station (Spielraum "Schlüpf-Animation"): the egg wobbles, then the pet
	-- shows with its rarity colour and stars.
	Reveal = table.freeze({
		WobbleSeconds = 0.6,
		WobbleDegrees = 15,
		WobbleSpeed = 30, -- radians per second
		ShowSeconds = 1.8,
	}),

	-- Studio-only test station (EggStationTestGeometry, ADR 0013), in studs. Not design values.
	StudioTest = table.freeze({
		AreaName = "EggTestZone",
		ZoneIndex = 1, -- Egg 1 sits in zone 1 (Config.Pets.EggZones)
		Distance = 14, -- in front of the target character
		BaseSize = table.freeze({ 6, 1, 6 }),
		EggSize = table.freeze({ 3, 4, 3 }),
		LabelHeight = 6, -- LabelAnchor above the base
	}),
}

return table.freeze(Eggs)

--!strict
-- Finds in the snow (concept 7.7, 8.5, ADR 0016). Startwerte. Values and chances per rarity are ✅.
-- English names are from the concept appendix. Launch: the Alps finds of World 1 and the secret
-- find; the finds of the other worlds come with their worlds (7.6b-7.6d).

local Finds = {
	SpawnInterval = 20, -- seconds; a point spawns a find if it holds none

	-- Chance per spawned find, in percent (Rarity ids from Config/Rarity).
	Odds = table.freeze({
		Common = 60,
		Uncommon = 25,
		Rare = 10,
		Epic = 4,
		Legendary = 1,
	}),
	-- Legendary finds exist only from this zone of each world on (zones 6 to 10). Below it the
	-- Legendary chance goes to LegendaryFallback (zones 1 to 5: Common 61 %).
	LegendaryFromZoneInWorld = 6,
	LegendaryFallback = "Common",

	-- Value as a fraction of a full ball of the current zone.
	Values = table.freeze({
		Common = 0.02,
		Uncommon = 0.05,
		Rare = 0.15,
		Epic = 0.5,
		Legendary = 2,
	}),

	-- Secret find (Yeti footprint): 1 in 2,000 per spawned find, in every world. Gives a title
	-- and a ball effect, no coin value.
	SecretChance = 1 / 2000,

	-- The find catalogue. Ids are the keys of sim.collection.finds in the save format: never
	-- rename an id. `World` is the world the find belongs to (nil: every world). `PopupKey` is a
	-- Config.Ui pop-up text shown on pickup; only finds of PopupRarities have one.
	Items = table.freeze({
		PineCone = table.freeze({ Name = "Pine Cone", Rarity = "Common", World = 1 }),
		ChocolateBar = table.freeze({ Name = "Chocolate Bar", Rarity = "Uncommon", World = 1 }),
		Edelweiss = table.freeze({ Name = "Edelweiss", Rarity = "Rare", World = 1 }),
		RockCrystal = table.freeze({
			Name = "Rock Crystal",
			Rarity = "Epic",
			World = 1,
			PopupKey = "FindRockCrystal",
		}),
		GoldenCowbell = table.freeze({
			Name = "Golden Cowbell",
			Rarity = "Legendary",
			World = 1,
			PopupKey = "FindGoldenCowbell",
		}),
		YetiFootprint = table.freeze({ Name = "Yeti Footprint", Rarity = "Secret", PopupKey = "FindYetiFootprint" }),
	}),

	-- The find a roll of each rarity gives, per world. Worlds 2 to 5 are added with their worlds.
	ByWorld = table.freeze({
		[1] = table.freeze({
			Common = "PineCone",
			Uncommon = "ChocolateBar",
			Rare = "Edelweiss",
			Epic = "RockCrystal",
			Legendary = "GoldenCowbell",
		}),
	}),
	SecretFind = "YetiFootprint",

	-- Reward of the secret find (7.7 "einen Titel und einen Ball-Effekt"). The title id is a key of
	-- sim.titles. The ball effect is shown while the player holds the title, so it needs no own
	-- save field. Title name: decided by Development (7.7 names no title).
	SecretTitle = "YetiTracker",
	TitleNames = table.freeze({
		YetiTracker = "Yeti Tracker",
	}),
	-- Title -> ball effect id. Server-written on the Player as BallEffectAttribute on every server
	-- (client contract); the client shows the effect on that player's ball.
	BallEffects = table.freeze({
		YetiTracker = "YetiSparkles",
	}),
	BallEffectAttribute = "FindBallEffect",

	-- "Sehr seltene Funde lösen eine kurze Einblendung aus" (7.7): these rarities show a pop-up.
	PopupRarities = table.freeze({
		Epic = true,
		Legendary = true,
		Secret = true,
	}),
	-- Second pop-up after the secret find: the new title (Config.Ui text key).
	TitlePopupKey = "FindNewTitle",

	-- Technical timing (not design values): how often the server looks for due spawns and for
	-- balls within reach of a find. A spawn is at most SpawnCheckInterval late.
	SpawnCheckInterval = 0.25,
	PickupCheckInterval = 0.1,

	-- How a find looks on the client (Spielraum 7.7: models and the spawn effect). Placeholders:
	-- a disc in the rarity colour with its stars (or crown) under it, never colour alone (8.5).
	-- Sizes in studs; a find further away than MaxDistance is not drawn (mobile, ADR 0003 R2).
	Visual = table.freeze({
		SizeStuds = 2.5,
		StrokeThickness = 2, -- px, white ring round the disc
		CornerShare = 0.5, -- UICorner radius as a share of the side: 0.5 draws a circle
		SymbolHeightShare = 0.4, -- of the billboard height, under the disc
		HeightAboveGround = 1.5, -- billboard centre above the point
		MaxDistance = 150,
		-- Finds stuck in the own ball (7.7 "Man sieht die Funde im Ball stecken"), up to
		-- MaxInBall of them; every find still counts for the sale. Size as a share of the ball's
		-- diameter, clamped to the stud limits.
		MaxInBall = 24,
		InBallShare = 0.22,
		InBallMinStuds = 0.6,
		InBallMaxStuds = 3,
		-- Ball effect of the secret find: Roblox's built-in Sparkles (no asset), in the Secret
		-- rarity colour. Other players' balls show it too.
		EffectName = "FindBallEffect",
	}),

	-- Studio-only test points (FindTestPoints, ADR 0016). They are put into the test zones of
	-- ZoneTestGeometry (Config.Map.ZoneTest): per zone, one FindPoint Attachment per entry, named
	-- NamePrefix .. k, in the zone's floor part, at { x, z } studs from the zone's start edge and
	-- from its centre line, on top of the floor. Not design values.
	Test = table.freeze({
		NamePrefix = "FindTestPoint",
		Points = table.freeze({
			table.freeze({ 36, -16 }),
			table.freeze({ 60, 14 }),
			table.freeze({ 84, -4 }),
		}),
	}),

	-- Read-only diagnostics, written only in Studio at PlaceId 0.
	DiagnosticAttributes = table.freeze({
		PointsState = "FindPointsState", -- on ServerScriptService
		Spawned = "FindSpawnedCount",
		SpawnedList = "FindSpawnedList",
		LastSpawn = "FindLastSpawn",
		LastSpawnSlot = "FindLastSpawnSlot",
		LastSpawnClock = "FindLastSpawnClock",
		LastRoll = "FindLastRoll",
		LastPickup = "FindLastPickup",
		LastPickupSlot = "FindLastPickupSlot",
		LastPickupClock = "FindLastPickupClock",
		LastPickupValue = "FindLastPickupValue",
		LastPickupZone = "FindLastPickupZone",
		LastRefusal = "FindLastRefusal",
		BallCount = "FindBallCount",
		BallList = "FindBallList",
		Collection = "FindCollection",
		CollectionCount = "FindCollectionCount",
		Titles = "FindTitles",
		MagnetRadius = "FindMagnetRadius",
		-- Client-local on the LocalPlayer (FindController).
		ClientVisible = "FindClientVisible",
		ClientInBall = "FindClientInBall",
	}),
}

return table.freeze(Finds)

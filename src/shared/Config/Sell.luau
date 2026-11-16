--!strict
-- Selling at the scale (concept 7.5, 8.3, ADR 0012). The formula and its bonus values are in
-- Config/Economy and Formulas.Economy.saleCoins; this module holds the technical values of the
-- scale binding, the sale rule and the "+3.4K" feedback. Spielraum (7.5: look of the scale,
-- animation, sound) unless a comment says otherwise. Distances in studs, times in seconds.

local Sell = {
	-- How often the server checks every ball against the scale plates.
	CheckInterval = 0.1,

	-- The ball touches a plate when the gap between its surface and the plate's box is at most
	-- TouchMargin (same slack as Config.Ball.CollisionContactMargin). After a sale, or a refused
	-- attempt, the next one needs the ball to have left every plate: a gap above ReleaseMargin.
	-- A ball shrunk to start size on the plate therefore cannot be sold again until it is
	-- pushed off and back on (ADR 0012 "One sale per visit").
	TouchMargin = 0.25,
	ReleaseMargin = 2,

	-- A sale must be worth at least this many coins. A ball just above start size is worth 0
	-- (zone 1: 10 * 0.2^3 = 0.08), and a "+0" that resets the ball would only confuse.
	MinSaleCoins = 1,

	-- CurrencyService reason of a sale (analytics, ADR 0007).
	CoinReason = "Sale",

	-- Server-written player attribute with the pet multiplier (PetService, #41). Missing or not
	-- a finite number >= 1: the sale uses 1.
	PetMultiplierAttribute = "PetMultiplier",

	-- Technical bound for the finds value one ball can carry (the Coins MaxChange of
	-- Config.Currency), so a broken caller cannot push an absurd value into a sale.
	MaxFindsValue = 1e30,

	-- "+3.4K" that flies to the Coins display (client, SaleController).
	Feedback = table.freeze({
		GuiName = "SaleFeedback",
		LabelName = "SaleGain",
		-- One above Config.Ui.DisplayOrder.Hud, so the label flies over the HUD panels.
		DisplayOrder = 11,
		-- The HUD the label flies to (#35, #90): PlayerGui[HudGuiName][CoinsPanelName].
		HudGuiName = "SimulatorHud",
		CoinsPanelName = "Coins",
		-- Start: centre of the screen, this share of its height from the top (over the ball).
		StartYFraction = 0.4,
		-- Label size before the HUD scale; shrinks to EndScale on the way.
		Width = 200,
		Height = 48,
		EndScale = 0.6,
		-- Shows at the start, flies, then fades out on the Coins display.
		ShowSeconds = 0.35,
		FlySeconds = 0.7,
		FadeSeconds = 0.3,
	}),

	-- Studio-only test scale (SellScaleTestGeometry, ADR 0012). Not design values.
	Test = table.freeze({
		AreaName = "SellScaleTest",
		DecoyName = "SellScaleTestDecoy",
		Distance = 24, -- studs from the character to the plate centre
		PlateSize = table.freeze({ 16, 1, 16 }), -- studs
		-- The plate's top is this far above the ground under it: no step, no z-fighting.
		PlateRaise = 0.05,
		AnchorHeight = 4, -- ScaleAnchor this far above the plate's top
		PlateColorRGB = table.freeze({ 255, 210, 60 }),
		GroundSearchHeight = 50,
		GroundSearchDepth = 200,
	}),

	-- Read-only diagnostics on the Player, written only in Studio at PlaceId 0.
	DiagnosticAttributes = table.freeze({
		LastSale = "SellLastSale",
		LastCoins = "SellLastCoins",
		LastSizeMetres = "SellLastSizeMetres",
		LastBallValue = "SellLastBallValue",
		LastFindsValue = "SellLastFindsValue",
		LastPetMultiplier = "SellLastPetMultiplier",
		LastRebirths = "SellLastRebirths",
		LastRebirthMultiplier = "SellLastRebirthMultiplier",
		LastSellValueLevel = "SellLastSellValueLevel",
		LastSellMultiplier = "SellLastSellMultiplier",
		LastBonus = "SellLastBonus",
		LastBonusFlags = "SellLastBonusFlags",
		LastZone = "SellLastZone",
		LastBalance = "SellLastBalance",
		LastRefusal = "SellLastRefusal",
		Sales = "SellCount",
		Refusals = "SellRefusals",
		FindsValue = "SellFindsValue",
		Touching = "SellTouching",
		Latched = "SellLatched",
	}),
}

return table.freeze(Sell)

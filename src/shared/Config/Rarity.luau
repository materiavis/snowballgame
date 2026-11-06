--!strict
-- Rarity tiers and how they are shown (concept 8.5, 10.3). A rarity is never shown by colour
-- alone: every tier has a colour, a symbol (stars or a crown) and an English name.
-- Colours are RGB 0..255 so this module stays loadable outside Roblox; Rarity.color3 converts.
-- Chances and powers per tier live with their feature: Config/Pets (eggs) and Config/Finds.

export type Tier = {
	Name: string,
	Stars: number, -- 0 = no stars, the symbol is shown instead
	Symbol: string?, -- shown instead of / next to the stars
	Color: { number }, -- { r, g, b }
	Rainbow: boolean?, -- the UI animates a rainbow; Color is its fallback
}

local Rarity = {
	-- Lowest to highest. Ids are the keys used in Config and in saved data.
	Order = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" }),

	StarSymbol = "★",

	Tiers = table.freeze({
		Common = table.freeze({ Name = "Common", Stars = 1, Color = table.freeze({ 158, 158, 158 }) }), -- grey
		Uncommon = table.freeze({ Name = "Uncommon", Stars = 2, Color = table.freeze({ 76, 175, 80 }) }), -- green
		Rare = table.freeze({ Name = "Rare", Stars = 3, Color = table.freeze({ 33, 150, 243 }) }), -- blue
		Epic = table.freeze({ Name = "Epic", Stars = 4, Color = table.freeze({ 156, 39, 176 }) }), -- purple
		Legendary = table.freeze({ Name = "Legendary", Stars = 5, Color = table.freeze({ 255, 193, 7 }) }), -- gold
		Secret = table.freeze({
			Name = "Secret",
			Stars = 0,
			Symbol = "👑", -- crown
			Color = table.freeze({ 255, 105, 180 }),
			Rainbow = true,
		}),
	} :: { [string]: Tier }),
}

return table.freeze(Rarity)

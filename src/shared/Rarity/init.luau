--!strict
-- Rarity bound to Config.Rarity (concept 8.5, ADR 0007). Adds color3() for Roblox UI; the
-- rest is the pure Tiers child. Show a rarity with label() or symbol + name, never colour alone.

local Config = script.Parent:WaitForChild("Config")
local Tiers = require(script:WaitForChild("Tiers"))

local rarity = Tiers.new(require(Config:WaitForChild("Rarity")) :: any)

return table.freeze({
	order = rarity.order,
	isRarity = rarity.isRarity,
	get = rarity.get,
	label = rarity.label,
	compare = rarity.compare,
	color3 = function(id: string): Color3
		local rgb = rarity.get(id).rgb
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end,
})

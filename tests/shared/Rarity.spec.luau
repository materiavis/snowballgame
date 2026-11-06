--!strict
-- Concept 8.5 / 10.3: a rarity is never shown by colour alone (issue #27 Fix).

local T = require("../TestKit")
local E = require("../helpers/Economy")

local Rarity = E.Rarity

return T.suite("Rarity (8.5)", function(test)
	test("tiers in order: Common to Legendary with 1 to 5 stars, Secret with a crown", function()
		T.equal(table.concat(Rarity.order, ","), "Common,Uncommon,Rare,Epic,Legendary,Secret")
		for stars, id in { "Common", "Uncommon", "Rare", "Epic", "Legendary" } do
			local info = Rarity.get(id)
			T.equal(info.stars, stars, id)
			T.equal(info.symbol, string.rep("★", stars), id)
			T.equal(info.rank, stars, id)
		end
		local secret = Rarity.get("Secret")
		T.equal(secret.symbol, "👑")
		T.isTrue(secret.rainbow, "secret is rainbow")
	end)

	test("every tier has a colour and a symbol and a name, and the label carries both", function()
		for _, id in Rarity.order do
			local info = Rarity.get(id)
			T.equal(#info.rgb, 3, `{id} colour`)
			for _, channel in info.rgb do
				T.isTrue(channel >= 0 and channel <= 255 and channel % 1 == 0, `{id} channel`)
			end
			T.isTrue(info.symbol ~= "", `{id} symbol`)
			T.equal(Rarity.label(id), `{info.symbol} {info.name}`)
		end
		T.equal(Rarity.label("Rare"), "★★★ Rare")
	end)

	test("8.5 colours: grey, green, blue, purple, gold are all different", function()
		local seen = {}
		for _, id in Rarity.order do
			local key = table.concat(Rarity.get(id).rgb, ",")
			T.equal(seen[key], nil, `{id} shares a colour`)
			seen[key] = true
		end
	end)

	test("a tier without stars or symbol is refused at load", function()
		local config = table.clone(E.Config.Rarity) :: any
		local tiers = table.clone(config.Tiers)
		tiers.Secret = { Name = "Secret", Stars = 0, Color = { 1, 2, 3 } }
		config.Tiers = tiers
		T.throws(function()
			E.Modules.Tiers.new(config)
		end, "never colour alone")
	end)

	test("compare sorts rarest first; unknown ids are errors", function()
		local list = { "Rare", "Common", "Secret", "Epic" }
		table.sort(list, Rarity.compare)
		T.equal(table.concat(list, ","), "Secret,Epic,Rare,Common")
		T.equal(Rarity.isRarity("Mythic"), false)
		T.throws(function()
			Rarity.get("Mythic")
		end, "unknown rarity")
	end)
end)

--!strict
-- Concept 7.8 upgrade costs and effects (issue #27 AC1).

local T = require("../../TestKit")
local E = require("../../helpers/Economy")

local Upgrades = E.Upgrades

-- 7.8 table: base price, factor, effect at level 0 and level 100.
local TABLE = {
	growth = { base = 25, factor = 1.35, start = 40, finish = 8 },
	walkSpeed = { base = 40, factor = 1.35, start = 16, finish = 32 },
	magnet = { base = 150, factor = 1.4, start = 4, finish = 24 },
	sellValue = { base = 200, factor = 1.45, start = 1, finish = 6 },
	stability = { base = 100, factor = 1.35, start = 0.1, finish = 0.02 },
}

return T.suite("Formulas.Upgrades (7.8)", function(test)
	test("cost = base price * factor^(level - 1), whole coins rounded down", function()
		for id, row in TABLE do
			T.equal(Upgrades.cost(id, 1), row.base, `{id} level 1`)
			T.equal(Upgrades.cost(id, 2), math.floor(row.base * row.factor * (1 + 1e-12)), `{id} level 2`)
			local top = row.base * row.factor ^ 99
			T.near(Upgrades.cost(id, 100), top, top * 1e-9 + 1, `{id} level 100`)
		end
		T.equal(Upgrades.cost("growth", 2), 33, "25 * 1.35 = 33.75")
	end)

	test("effects run linearly from level 0 to level 100", function()
		for id, row in TABLE do
			T.near(Upgrades.effect(id, 0), row.start, 1e-12, `{id} level 0`)
			T.near(Upgrades.effect(id, 100), row.finish, 1e-12, `{id} level 100`)
			T.near(Upgrades.effect(id, 50), (row.start + row.finish) / 2, 1e-12, `{id} level 50`)
		end
		T.near(Upgrades.effect("sellValue", 1), 1.05, 1e-12, "+5 % per level")
	end)

	test("level 100 is the maximum", function()
		T.equal(Upgrades.maxLevel, 100)
		T.equal(Upgrades.nextCost("magnet", 0), 150)
		T.equal(Upgrades.nextCost("magnet", 100), nil)
		T.throws(function()
			Upgrades.cost("magnet", 101)
		end, "level must be")
		T.throws(function()
			Upgrades.cost("magnet", 0)
		end, "level must be")
		T.throws(function()
			Upgrades.effect("magnet", 2.5)
		end, "level must be")
		T.throws(function()
			Upgrades.cost("jump", 1)
		end, "unknown upgrade")
	end)
end)

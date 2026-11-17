--!strict
-- Shared zone helpers (#39): the ZonesUnlocked text form and the missing amount rounded up so
-- the pop-up ("Need {1} more", NumberFormat.number) shows what NumberFormat.price shows.

local T = require("../TestKit")
local E = require("../helpers/Economy")
local DisplayConfig = require("../../src/shared/Config/Display")
local PopupAmount = require("../../src/shared/PopupAmount")
local ZoneAttributes = require("../../src/shared/ZoneAttributes")

local up = PopupAmount.new(DisplayConfig :: any)

return T.suite("Zone shared helpers (#39)", function(test)
	test("ZonesUnlocked: encode sorts and drops duplicates, decode is strict", function()
		T.equal(ZoneAttributes.encode({ 3, 1, 2, 2 }), "1,2,3")
		T.equal(ZoneAttributes.encode({}), "")
		T.equal(table.concat(ZoneAttributes.decode("2,1", E.Zones.isZone) :: { number }, ","), "1,2")
		for _, bad in { "", "1,", "a", "1, 2", "2.0", "-1", "0", "51", 5 } :: { any } do
			T.equal(ZoneAttributes.decode(bad, E.Zones.isZone), nil, tostring(bad))
		end
	end)

	test("missing amount: the pop-up text equals the price text, never less", function()
		T.equal(E.NumberFormat.number(up(1150)), "1.2K", "the upgrade example of 2026-11-12")
		T.equal(E.NumberFormat.number(up(220)), "220")
		T.equal(E.NumberFormat.number(up(999.5)), "1K")
		local values = { 1, 9, 999, 1000, 1001, 1049, 1050, 1099, 1100, 29999, 30001, 999949, 999950, 3755901 }
		local value = 1.37
		while value < 1e24 do
			table.insert(values, value)
			value *= 2.71
		end
		for _, amount in values do
			T.equal(E.NumberFormat.number(up(amount)), E.NumberFormat.price(amount), tostring(amount))
			T.isTrue(up(amount) >= amount * (1 - 1e-12), `never below the amount {amount}`)
		end
	end)

	test("missing amount: invalid input is an error", function()
		T.throws(function()
			up(-1)
		end)
		T.throws(function()
			up(0 / 0)
		end)
	end)
end)

--!strict
-- Concept 10.3 / 7.4 / 7.5 number and size text (issue #27 AC2).

local T = require("../TestKit")
local E = require("../helpers/Economy")

local Format = E.NumberFormat

local function nearest(): any
	local config = table.clone(E.Config.Display) :: any
	config.Rounding = "Nearest"
	return E.Modules.Formatter.new(config)
end

return T.suite("NumberFormat (10.3)", function(test)
	test("below 1'000 numbers are written out", function()
		T.equal(Format.number(0), "0")
		T.equal(Format.number(80), "80")
		T.equal(Format.number(320), "320")
		T.equal(Format.number(999), "999")
	end)

	test("from 1'000: K, M, B, T, Qa, Qi, Sx with one decimal", function()
		T.equal(Format.number(1000), "1K")
		T.equal(Format.number(3400), "3.4K")
		T.equal(Format.number(33087), "33K")
		T.equal(Format.number(3755901), "3.7M")
		T.equal(Format.number(1.2e9), "1.2B")
		T.equal(Format.number(3.2e12), "3.2T")
		T.equal(Format.number(7e15), "7Qa")
		T.equal(Format.number(4.6e18), "4.6Qi")
		T.equal(Format.number(4.6e21), "4.6Sx")
	end)

	test("the concept examples: +3.4K and Zone 6 · 3.7M", function()
		T.equal(Format.signed(3400), "+3.4K")
		T.equal(Format.signed(3449), "+3.4K")
		T.equal(Format.number(3.7e6), "3.7M")
		T.equal(Format.signed(-1500), "-1.5K")
		T.equal(Format.signed(0), "+0")
	end)

	test("rounding down never shows more than the value and never 1000K", function()
		T.equal(Format.number(999999), "999.9K")
		T.equal(Format.number(1999), "1.9K")
		T.equal(Format.number(999.99), "999")
		T.equal(Format.number(-3449), "-3.4K")
	end)

	test("beyond Sx the last suffix stays", function()
		T.equal(Format.number(1.5e24), "1500Sx")
	end)

	test("ball size: metres with one decimal and a decimal point", function()
		T.equal(Format.size(4.7), "4.7 m")
		T.equal(Format.size(4.71), "4.7 m")
		T.equal(Format.size(2), "2.0 m")
		T.equal(Format.size(0.2), "0.2 m")
		T.equal(Format.size(E.Zones.maxSize(5)), "4.8 m")
		T.equal(Format.size(E.Zones.maxSize(25)), "423.5 m")
	end)

	test("7.4: metres up to 999.9 m, then kilometres", function()
		T.equal(Format.size(999.9), "999.9 m")
		T.equal(Format.size(999.99), "999.9 m")
		T.equal(Format.size(1000), "1.0 km")
		T.equal(Format.size(1250), "1.2 km")
		T.equal(Format.size(E.Zones.maxSize(49)), "89.6 km")
	end)

	test("Nearest rounding also switches suffix and unit after rounding", function()
		local format = nearest()
		T.equal(format.number(3449), "3.4K")
		T.equal(format.number(3450), "3.5K")
		T.equal(format.number(3755901), "3.8M")
		T.equal(format.number(999.6), "1K")
		T.equal(format.number(999950), "1M")
		T.equal(format.size(4.75), "4.8 m")
		T.equal(format.size(999.96), "1.0 km")
	end)

	test("non-numbers, NaN, infinity and negative sizes are errors", function()
		T.throws(function()
			Format.number(0 / 0)
		end, "finite")
		T.throws(function()
			Format.number(math.huge)
		end, "finite")
		T.throws(function()
			Format.size(-1)
		end, "negative")
		T.throws(function()
			Format.number("5" :: any)
		end, "finite")
	end)
end)

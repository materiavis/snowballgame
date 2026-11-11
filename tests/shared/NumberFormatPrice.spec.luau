--!strict
-- Prices round up, balances round down (issue #88, owner decision 2026-11-06, concept 7.6, 10.3).

local T = require("../TestKit")
local E = require("../helpers/Economy")

local Format = E.NumberFormat
local Display = E.Config.Display

local function withPriceRounding(mode: string): any
	local config = table.clone(Display) :: any
	config.PriceRounding = mode
	return E.Modules.Formatter.new(config)
end

return T.suite("NumberFormat prices (#88)", function(test)
	test("Config.Display: balances Floor, prices Ceil", function()
		T.equal(Display.Rounding, "Floor")
		T.equal(Display.PriceRounding, "Ceil")
	end)

	test("zone 10 barrier 3,755,901: price 3.8M, balance 3.7M", function()
		local barrier = E.Zones.barrierPrice(10)
		T.equal(barrier, 3755901)
		T.equal(Format.price(barrier), "3.8M")
		T.equal(Format.number(barrier), "3.7M")
	end)

	test("prices below 1'000 are whole numbers shown exactly", function()
		T.equal(Format.price(0), "0")
		T.equal(Format.price(1), "1")
		T.equal(Format.price(80), "80")
		T.equal(Format.price(320), "320")
		T.equal(Format.price(999), "999")
	end)

	test("a fraction below 1'000 rounds up, to 1K at the step", function()
		T.equal(Format.price(998.2), "999")
		T.equal(Format.price(999.2), "1K")
	end)

	test("values exact in decimal keep their digit when rounding up", function()
		T.equal(Format.price(1000), "1K")
		T.equal(Format.price(3400), "3.4K")
		T.equal(Format.price(4700), "4.7K")
		T.equal(Format.price(3.7e6), "3.7M")
		T.equal(Format.price(1.2e9), "1.2B")
		T.equal(Format.price(3.2e12), "3.2T")
		T.equal(Format.price(7e15), "7Qa")
		T.equal(Format.price(4.6e18), "4.6Qi")
		T.equal(Format.price(4.6e21), "4.6Sx")
	end)

	test("anything above a shown step rounds up to the next decimal", function()
		T.equal(Format.price(1001), "1.1K")
		T.equal(Format.price(3401), "3.5K")
		T.equal(Format.price(1000001), "1.1M")
	end)

	test("at every suffix step the suffix is picked after rounding up", function()
		T.equal(Format.price(999950), "1M")
		T.equal(Format.price(999901), "1M")
		T.equal(Format.price(999900), "999.9K")
		local suffixes = Display.Suffixes
		local step = Display.SuffixStep
		for i = 1, #suffixes - 1 do
			local unit = step ^ i
			local label = `step {suffixes[i]} -> {suffixes[i + 1]}`
			T.equal(Format.price(999.95 * unit), `1{suffixes[i + 1]}`, label)
			T.equal(Format.price(step * unit), `1{suffixes[i + 1]}`, label)
			T.equal(Format.price(999.9 * unit), `999.9{suffixes[i]}`, label)
			-- The balance of the same value never rounds up into the next suffix.
			T.equal(Format.number(999.95 * unit), `999.9{suffixes[i]}`, label)
		end
	end)

	test("beyond Sx the last suffix stays, as for balances", function()
		T.equal(Format.price(1.5e24), "1500Sx")
		T.equal(Format.price(999.95e21), "1000Sx")
	end)

	-- Owner decision 2026-11-10 (#100): a negative price is an error, not "-3.8M".
	test("negative prices are errors, zero is 0", function()
		for _, value in { -1, -999, -3755901, -999950, -0.5 } do
			T.throws(function()
				Format.price(value)
			end, "price must not be negative", `price({value})`)
		end
		local message = T.throws(function()
			Format.price(-3755901)
		end)
		T.isTrue(string.find(message, "got -3755901", 1, true), "message names the value")
		T.equal(Format.price(0), "0")
	end)

	test("-0 is not negative and shows 0", function()
		T.equal(Format.price(-0), "0")
	end)

	test("balances, gains and sizes keep their negative handling", function()
		T.equal(Format.number(-3755901), "-3.7M")
		T.equal(Format.signed(-3400), "-3.4K")
		T.throws(function()
			Format.size(-1)
		end, "size must not be negative")
	end)

	test("non-numbers, NaN and infinity are errors", function()
		T.throws(function()
			Format.price(0 / 0)
		end, "finite")
		T.throws(function()
			Format.price(math.huge)
		end, "finite")
		T.throws(function()
			Format.price(-math.huge)
		end, "finite")
		T.throws(function()
			Format.price("5" :: any)
		end, "finite")
	end)

	test("PriceRounding switches only price, not number, signed or size", function()
		local floor = withPriceRounding("Floor")
		T.equal(floor.price(3755901), "3.7M")
		T.equal(floor.price(999950), "999.9K")
		local nearest = withPriceRounding("Nearest")
		T.equal(nearest.price(3755901), "3.8M")
		T.equal(nearest.price(3449), "3.4K")
		for _, format in { floor, nearest, Format } do
			T.equal(format.number(3755901), "3.7M")
			T.equal(format.signed(3449), "+3.4K")
			T.equal(format.size(999.99), "999.9 m")
			T.equal(format.size(1250), "1.2 km")
		end
	end)

	test("an unknown PriceRounding is refused", function()
		T.throws(function()
			withPriceRounding("Up")
		end, "PriceRounding")
	end)
end)

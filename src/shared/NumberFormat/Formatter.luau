--!strict
-- Number and size text (concept 7.4, 7.5, 10.3). Pure: the display config is passed to new(),
-- NumberFormat/init.luau binds it to Config.Display.
--   number(3400)    -> "3.4K"    signed(3400)   -> "+3.4K"
--   number(3755901) -> "3.7M"    price(3755901) -> "3.8M"
--   size(4.71)      -> "4.7 m"   size(1250)     -> "1.2 km"
-- The suffix or unit is picked after rounding, so "1000K" and "1000.0 m" never appear.

export type DisplayConfig = {
	Suffixes: { string },
	SuffixStep: number,
	NumberDecimals: number,
	TrimZeroDecimal: boolean,
	SizeDecimals: number,
	MetresPerKilometre: number,
	MetreUnit: string,
	KilometreUnit: string,
	Rounding: "Floor" | "Nearest",
	PriceRounding: "Ceil" | "Floor" | "Nearest",
}

export type Formatter = {
	number: (value: number) -> string,
	signed: (value: number) -> string,
	price: (value: number) -> string,
	size: (metres: number) -> string,
}

type Mode = "Ceil" | "Floor" | "Nearest"

local Formatter = {}

local function checkFinite(value: any, what: string)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		error(`NumberFormat: {what} must be a finite number, got {tostring(value)}`, 3)
	end
end

function Formatter.new(config: DisplayConfig): Formatter
	assert(config.Rounding == "Floor" or config.Rounding == "Nearest", "NumberFormat: Rounding is Floor or Nearest")
	assert(
		config.PriceRounding == "Ceil" or config.PriceRounding == "Floor" or config.PriceRounding == "Nearest",
		"NumberFormat: PriceRounding is Ceil, Floor or Nearest"
	)

	-- Rounds a non-negative value to `decimals` places. Floor and Ceil get a tiny relative
	-- nudge so a value that is exact in decimal (4.7) but not in binary (4.69999... or
	-- 4.70000...1) keeps its last digit instead of losing or gaining one.
	local function round(value: number, decimals: number, mode: Mode): number
		local scale = 10 ^ decimals
		if mode == "Floor" then
			return math.floor(value * scale * (1 + 1e-12)) / scale
		elseif mode == "Ceil" then
			return math.ceil(value * scale * (1 - 1e-12)) / scale
		end
		return math.floor(value * scale + 0.5) / scale
	end

	local function fixed(value: number, decimals: number, trim: boolean): string
		local text = string.format(`%.{decimals}f`, value)
		if trim and decimals > 0 then
			text = string.gsub(text, "%.0+$", "")
		end
		return text
	end

	-- `value` is already checked. The mode applies to the magnitude, so a negative value
	-- mirrors its positive one.
	local function abbreviate(value: number, mode: Mode): string
		local sign = if value < 0 then "-" else ""
		local magnitude = math.abs(value)

		-- Tier 0 is plain whole numbers below SuffixStep; tier i uses Suffixes[i]. Each tier is
		-- rounded before the comparison, so a value that rounds up to SuffixStep moves on.
		local tier, scaled = 0, round(magnitude, 0, mode)
		while scaled >= config.SuffixStep and tier < #config.Suffixes do
			tier += 1
			scaled = round(magnitude / config.SuffixStep ^ tier, config.NumberDecimals, mode)
		end
		if tier == 0 then
			return sign .. fixed(scaled, 0, false)
		end
		return sign .. fixed(scaled, config.NumberDecimals, config.TrimZeroDecimal) .. config.Suffixes[tier]
	end

	-- Balances and other amounts the player holds (Display.Rounding).
	local function number(value: number): string
		checkFinite(value, "value")
		return abbreviate(value, config.Rounding)
	end

	-- For gains shown in the HUD ("+3.4K", 7.5). Zero counts as a gain.
	local function signed(value: number): string
		checkFinite(value, "value")
		if value < 0 then
			return number(value)
		end
		return "+" .. number(value)
	end

	-- Costs (Display.PriceRounding). Rounded up, a shown price is never less than the cost.
	local function price(value: number): string
		checkFinite(value, "price")
		return abbreviate(value, config.PriceRounding)
	end

	-- Ball size: metres up to 999.9 m, then kilometres, always SizeDecimals places (7.4).
	local function size(metres: number): string
		checkFinite(metres, "size")
		if metres < 0 then
			error(`NumberFormat: size must not be negative, got {metres}`, 2)
		end
		local inMetres = round(metres, config.SizeDecimals, config.Rounding)
		if inMetres < config.MetresPerKilometre then
			return `{fixed(inMetres, config.SizeDecimals, false)} {config.MetreUnit}`
		end
		local inKilometres = round(metres / config.MetresPerKilometre, config.SizeDecimals, config.Rounding)
		return `{fixed(inKilometres, config.SizeDecimals, false)} {config.KilometreUnit}`
	end

	return table.freeze({ number = number, signed = signed, price = price, size = size })
end

return table.freeze(Formatter)

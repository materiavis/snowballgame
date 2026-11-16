--!strict
-- Rounds a missing amount up to the value NumberFormat.number shows unchanged (#39, ADR 0014).
-- Pure; the display config (Config.Display) is passed in.
--
-- Pop-up numbers are formatted with NumberFormat.number, which rounds down (balances, ADR 0007).
-- A missing price must never look smaller than it is ("Need 1.2K more" for 1,150, like the
-- upgrade window, owner decision 2026-11-12), so the amount is rounded up first, at the precision
-- NumberFormat.price uses: NumberFormat.number(up(x)) == NumberFormat.price(x).

export type DisplayConfig = {
	Suffixes: { string },
	SuffixStep: number,
	NumberDecimals: number,
}

local PopupAmount = {}

function PopupAmount.new(config: DisplayConfig): (value: number) -> number
	-- Same nudge as Formatter's Ceil, so a value exact in decimal is not pushed up a digit.
	local function ceilAt(value: number, decimals: number): number
		local scale = 10 ^ decimals
		return math.ceil(value * scale * (1 - 1e-12)) / scale
	end

	return function(value: number): number
		if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
			error(`PopupAmount: amount must be a finite number >= 0, got {tostring(value)}`, 2)
		end
		local tier, scaled = 0, ceilAt(value, 0)
		while scaled >= config.SuffixStep and tier < #config.Suffixes do
			tier += 1
			scaled = ceilAt(value / config.SuffixStep ^ tier, config.NumberDecimals)
		end
		return scaled * config.SuffixStep ^ tier
	end
end

return table.freeze(PopupAmount)

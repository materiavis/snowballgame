--!strict
-- Seeded weighted rolls (ADR 0003 "Rng", ADR 0007). Rolls that decide rewards run on the
-- server only; the client may read eggOdds/findOdds to show the chances (8.5).
-- Rng.new(seed?) wraps Roblox Random; the pure children (Weighted, Odds) take any
-- { next: () -> number } generator, which is how the headless tests seed them.

local Config = script.Parent:WaitForChild("Config")
local Formulas = require(script.Parent:WaitForChild("Formulas"))
local Odds = require(script:WaitForChild("Odds"))
local Weighted = require(script:WaitForChild("Weighted"))

local odds = Odds.new({
	order = (require(Config:WaitForChild("Rarity")) :: any).Order,
	pets = require(Config:WaitForChild("Pets")) :: any,
	finds = require(Config:WaitForChild("Finds")) :: any,
}, Formulas.Zones, Weighted)

-- Mirrors Odds.Generator (types of WaitForChild requires are not visible here).
export type Generator = { next: () -> number }

-- A generator over Roblox Random. Without a seed Random picks one; a seed makes a run
-- repeatable (for a Studio check). One generator per purpose keeps sequences independent.
local function new(seed: number?): Generator
	local random = if seed ~= nil then Random.new(seed) else Random.new()
	return table.freeze({
		next = function(): number
			return random:NextNumber()
		end,
	})
end

return table.freeze({
	new = new,
	pick = Weighted.pick,
	eggOdds = odds.eggOdds,
	findOdds = odds.findOdds,
	rollEgg = odds.rollEgg,
	rollFind = odds.rollFind,
})

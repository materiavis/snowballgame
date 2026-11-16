--!strict
-- The pet catalogue bound to Config.Pets, Config.Eggs, Config.Rarity and Formulas.Pets (ADR 0013).
-- The lookups are in the pure Catalogue child, so `lune run tests` checks the shipped catalogue.

local Config = script.Parent:WaitForChild("Config")
local Formulas = require(script.Parent:WaitForChild("Formulas")) :: any
local Catalogue = require(script:WaitForChild("Catalogue"))

return Catalogue.new(
	require(Config:WaitForChild("Pets")) :: any,
	require(Config:WaitForChild("Eggs")) :: any,
	(require(Config:WaitForChild("Rarity")) :: any).Order,
	Formulas.Pets.petBonus
)

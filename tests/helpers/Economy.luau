--!strict
-- Binds the pure economy modules to the real Config, the same way the Roblox init.luau files
-- (Formulas, NumberFormat, Rarity, Rng) do. Specs use this so they test the shipped values.

local Config = {
	Zones = require("../../src/shared/Config/Zones"),
	Pets = require("../../src/shared/Config/Pets"),
	Upgrades = require("../../src/shared/Config/Upgrades"),
	Economy = require("../../src/shared/Config/Economy"),
	Finds = require("../../src/shared/Config/Finds"),
	Rarity = require("../../src/shared/Config/Rarity"),
	Display = require("../../src/shared/Config/Display"),
}

local ZonesFormulas = require("../../src/shared/Formulas/Zones")
local PetsFormulas = require("../../src/shared/Formulas/Pets")
local UpgradesFormulas = require("../../src/shared/Formulas/Upgrades")
local EconomyFormulas = require("../../src/shared/Formulas/Economy")
local Formatter = require("../../src/shared/NumberFormat/Formatter")
local Tiers = require("../../src/shared/Rarity/Tiers")
local Odds = require("../../src/shared/Rng/Odds")
local Weighted = require("../../src/shared/Rng/Weighted")

local zones = ZonesFormulas.new(Config.Zones :: any)

return table.freeze({
	Config = Config,
	Zones = zones,
	Pets = PetsFormulas.new(Config.Pets :: any, zones),
	Upgrades = UpgradesFormulas.new(Config.Upgrades :: any),
	Economy = EconomyFormulas.new(Config.Economy :: any, Config.Finds :: any, zones),
	NumberFormat = Formatter.new(Config.Display :: any),
	Rarity = Tiers.new(Config.Rarity :: any),
	Odds = Odds.new({
		order = Config.Rarity.Order,
		pets = Config.Pets :: any,
		finds = Config.Finds :: any,
	}, zones, Weighted),
	Weighted = Weighted,
	-- Module tables for specs that build variants with changed config.
	Modules = table.freeze({
		Zones = ZonesFormulas,
		Formatter = Formatter,
		Tiers = Tiers,
		Odds = Odds,
	}),
})

--!strict
-- Economy formulas bound to their Config modules (ADR 0003 "Configuration", ADR 0007).
-- The child modules are pure and take their config in new(); only this file knows the
-- Instance tree, so `lune run tests` loads the children directly with the real config.
-- Shared by server and client: the server always recomputes, the client only previews.

local Config = script.Parent:WaitForChild("Config")

local EconomyFormulas = require(script:WaitForChild("Economy"))
local PetsFormulas = require(script:WaitForChild("Pets"))
local UpgradesFormulas = require(script:WaitForChild("Upgrades"))
local ZonesFormulas = require(script:WaitForChild("Zones"))

local zones = ZonesFormulas.new(require(Config:WaitForChild("Zones")) :: any)

return table.freeze({
	Zones = zones,
	Pets = PetsFormulas.new(require(Config:WaitForChild("Pets")) :: any, zones),
	Upgrades = UpgradesFormulas.new(require(Config:WaitForChild("Upgrades")) :: any),
	Economy = EconomyFormulas.new(
		require(Config:WaitForChild("Economy")) :: any,
		require(Config:WaitForChild("Finds")) :: any,
		zones
	),
})

--!strict
-- NumberFormat bound to Config.Display (concept 10.3, ADR 0007). Use NumberFormat.number,
-- NumberFormat.signed, NumberFormat.price and NumberFormat.size; the logic is in the pure Formatter child.

local Config = script.Parent:WaitForChild("Config")
local Formatter = require(script:WaitForChild("Formatter"))

return Formatter.new(require(Config:WaitForChild("Display")) :: any)

--!strict
-- Builds zone files from zone plans. Run from the repository root:
--   lune run tools/world/build <world>          all zones of the world
--   lune run tools/world/build <world> <zone>   one zone, e.g. 3
-- See tools/world/Builder.luau for the plan format.

local process = require("@lune/process")

local Builder = require("./Builder")
local Rules = require("../../src/shared/Config/WorldRules")

local world = process.args[1]
local zone = if process.args[2] then tonumber(process.args[2]) else nil
if not world or (process.args[2] and not zone) then
	print("usage: lune run tools/world/build <world> [zone]")
	process.exit(2)
end

local report = Builder.run(".", world :: string, zone, Rules)
for _, line in report.lines do
	print(line)
end
process.exit(if report.ok then 0 else 1)

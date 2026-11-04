--!strict
-- Loads real modules from src/ to show the pattern feature tests follow: require by relative
-- path from the spec file. Only pure modules work here; anything touching `game`, services or
-- Instances at require time (e.g. src/shared/PlaceInfo.luau) cannot load under Lune.
-- These checks are structural, not tuning values.

local T = require("../TestKit")
local Config = require("../../src/shared/Config")
local Places = require("../../src/shared/Config/Places")

local function isPlaceId(value: any): boolean
	return type(value) == "number" and value >= 0 and value % 1 == 0
end

return T.suite("src/shared/Config", function(test)
	test("Config loads and is frozen", function()
		T.equal(type(Config.Version), "string")
		T.isTrue(table.isfrozen(Config), "Config is frozen")
	end)

	test("Places holds a whole, non-negative PlaceId per Place", function()
		T.isTrue(table.isfrozen(Places), "Places is frozen")
		T.isTrue(table.isfrozen(Places.Worlds), "Places.Worlds is frozen")
		T.isTrue(isPlaceId(Places.Lobby), "Lobby")
		T.isTrue(isPlaceId(Places.Arena), "Arena")
		T.isTrue(Places.Worlds[1] ~= nil, "World 1 is listed")
		for worldIndex, placeId in Places.Worlds do
			T.isTrue(isPlaceId(placeId), `World {worldIndex}`)
		end
	end)
end)

--!strict
-- #90: BallService publishes the zone as the player attribute Config.Ball.PlayerZoneAttribute
-- next to BallSizeMetres and BallIsMax, on every server (not only with Studio diagnostics), so the
-- HUD's progress bar reads it from the server.

local T = require("../../../TestKit")
local SourceSection = require("../../../helpers/SourceSection")
local BallConfig = require("../../../../src/shared/Config/Ball") :: any

local PATH = "src/places/simulator/server/BallService/BallAttributes.luau"

return T.suite("BallService zone attribute (#90)", function(test)
	test("the attribute name is BallZone", function()
		T.equal(BallConfig.PlayerZoneAttribute, "BallZone")
	end)

	test("publish writes the zone on the player next to the size, outside the diagnostics", function()
		local publish = SourceSection.between(PATH, "local function publish(", "return table.freeze({ publish")
		local zoneAt =
			string.find(publish, "setOn(player, sentPlayer, config.PlayerZoneAttribute, state.zone)", 1, true)
		T.isTrue(zoneAt ~= nil, "zone written on the player")
		local sizeAt = string.find(publish, "config.PlayerSizeMetresAttribute", 1, true) :: number
		local diagnosticsAt = string.find(publish, "if diagnostics then", 1, true) :: number
		T.isTrue(
			(zoneAt :: number) > sizeAt and (zoneAt :: number) < diagnosticsAt,
			"next to the size, not Studio-only"
		)
	end)
end)

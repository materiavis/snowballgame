--!strict
-- "+3.4K" flies to the Coins display (#38 AC2, ADR 0012): start and target of the label on real
-- screen sizes, with the Coins panel where the Simulator HUD puts it (Layout.hud).

local T = require("../../../TestKit")
local Ui = require("../../../../src/shared/Config/Ui")
local SellConfig = require("../../../../src/shared/Config/Sell")
local Layout = require("../../../../src/client/Ui/Layout")
local FlightPath = require("../../../../src/places/simulator/client/SaleController/FlightPath")

local SCREENS = {
	{ width = 667, height = 375, touch = true }, -- iPhone SE landscape
	{ width = 932, height = 430, touch = true },
	{ width = 1024, height = 744, touch = true },
	{ width = 1920, height = 1080, touch = false },
}

return T.suite("SaleController.FlightPath (AC2)", function(test)
	test("the label starts in the middle and lands on the centre of the Coins panel", function()
		for _, screen in SCREENS do
			local hud = Layout.hud(screen :: any, Ui, 1)
			local coins = hud.coins
			local from = FlightPath.start(screen.width, screen.height, SellConfig.Feedback.StartYFraction)
			T.equal(from.x, screen.width / 2)
			local to = FlightPath.target(coins.x, coins.y, coins.width, coins.height, 0, 0)
			T.isTrue(
				FlightPath.inside(to, coins.x, coins.y, coins.width, coins.height),
				`{screen.width} lands in Coins`
			)
			T.equal(to.x, coins.x + coins.width / 2)
			T.isTrue(not FlightPath.inside(from, coins.x, coins.y, coins.width, coins.height), "starts elsewhere")
		end
	end)

	test("a gui with another origin still hits the panel", function()
		local to = FlightPath.target(110, 60, 150, 52, 10, 20)
		T.equal(to.x, 175)
		T.equal(to.y, 66)
	end)

	test("the HUD it flies to is the Simulator HUD's Coins panel", function()
		T.equal(SellConfig.Feedback.HudGuiName, "SimulatorHud")
		T.equal(SellConfig.Feedback.CoinsPanelName, "Coins")
		T.isTrue(SellConfig.Feedback.DisplayOrder > Ui.DisplayOrder.Hud, "flies over the HUD")
	end)
end)

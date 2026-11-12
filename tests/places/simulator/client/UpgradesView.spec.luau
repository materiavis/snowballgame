--!strict
-- Upgrades window rows (#36 AC1, AC3, ADR 0010): level x/100, effect now -> after the next level,
-- the price with price rounding, the buy state, MAX at level 100 and "–" while not loaded. Row
-- layout keeps the 44 px floor on the smallest screens of ADR 0008.

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local Ui = require("../../../../src/shared/Config/Ui")
local Layout = require("../../../../src/client/Ui/Layout")
local UpgradesView = require("../../../../src/places/simulator/client/SimulatorHudController/UpgradesView")

local Upgrades = E.Config.Upgrades

local function input(levels: { [string]: any }, coins: any, status: any?): UpgradesView.Input
	return {
		upgrades = Upgrades,
		formulas = E.Upgrades,
		formatPrice = E.NumberFormat.price,
		ui = Ui,
		status = if status == nil then "Loaded" else status,
		coins = coins,
		levels = levels,
	}
end

local ZERO = { growth = 0, walkSpeed = 0, magnet = 0, sellValue = 0, stability = 0 }

local function byId(rows: { UpgradesView.Row }): { [string]: UpgradesView.Row }
	local out = {}
	for _, row in rows do
		out[row.id] = row
	end
	return out
end

return T.suite("Upgrades window rows (7.8)", function(test)
	test("AC1: one row per upgrade, in Config order, with a name from Config.Ui", function()
		local rows = UpgradesView.rows(input(ZERO, 0))
		T.equal(#rows, 5)
		for index, id in Upgrades.Order do
			T.equal(rows[index].id, id)
			T.equal(rows[index].name, Ui.UpgradeRows[id].Name)
		end
	end)

	test("AC3: level 0 shows the effect now and after the next level", function()
		local rows = byId(UpgradesView.rows(input(ZERO, 1000)))
		T.equal(rows.growth.levelText, "0/100")
		T.equal(rows.growth.effectText, "40.00 → 39.68 s to MAX")
		T.equal(rows.walkSpeed.effectText, "16.00 → 16.16 studs/s")
		T.equal(rows.magnet.effectText, "4.0 → 4.2 studs")
		T.equal(rows.sellValue.effectText, "×1.00 → ×1.05")
		T.equal(rows.stability.effectText, "10.00 → 9.92 % lost per hit")
	end)

	test("AC2: the price is the next level's formula price, shown with price rounding", function()
		local rows = byId(UpgradesView.rows(input(ZERO, 1000)))
		T.equal(rows.growth.priceText, "25")
		T.equal(rows.walkSpeed.priceText, "40")
		T.equal(rows.magnet.priceText, "150")
		T.equal(rows.sellValue.priceText, "200")
		T.equal(rows.stability.priceText, "100")

		local levels = table.clone(ZERO)
		levels.sellValue = 30
		local row = UpgradesView.row(input(levels, 0), "sellValue")
		T.equal(row.priceText, E.NumberFormat.price(E.Upgrades.cost("sellValue", 31)))
		T.equal(row.levelText, "30/100")
	end)

	test("buy state follows the coins: Buy when affordable, 'Need coins' otherwise", function()
		local rows = byId(UpgradesView.rows(input(ZERO, 100)))
		T.equal(rows.growth.state, "Buy")
		T.equal(rows.growth.canBuy, true)
		T.equal(rows.growth.buttonText, Ui.Text.UpgradeBuy)
		T.equal(rows.stability.state, "Buy", "exactly the price is enough")
		T.equal(rows.magnet.state, "TooFewCoins")
		T.equal(rows.magnet.canBuy, false)
		T.equal(rows.magnet.buttonText, Ui.Text.UpgradeTooFewCoins)
	end)

	test("AC2: level 100 shows MAX, the final effect and no buy", function()
		local levels = table.clone(ZERO)
		levels.walkSpeed = 100
		local row = UpgradesView.row(input(levels, 1e30), "walkSpeed")
		T.equal(row.state, "Max")
		T.equal(row.canBuy, false)
		T.equal(row.levelText, "100/100")
		T.equal(row.effectText, "32.00 studs/s")
		T.equal(row.priceText, Ui.Text.UpgradeMax)
	end)

	test("not loaded, a missing or broken level, or a broken balance never offers a purchase", function()
		for _, status in { "Loading", "Failed", "Lost", "Teleported", "Released", 5 } do
			local row = UpgradesView.row(input(ZERO, 1000, status), "growth")
			T.equal(row.state, "Unavailable", tostring(status))
			T.equal(row.levelText, Ui.Text.Missing)
			T.equal(row.priceText, Ui.Text.Missing)
		end
		for _, broken in { -1, 101, 2.5, 0 / 0, "3" } do
			local levels = table.clone(ZERO) :: { [string]: any }
			levels.growth = broken
			T.equal(UpgradesView.row(input(levels, 1000), "growth").state, "Unavailable", tostring(broken))
		end
		T.equal(UpgradesView.row(input({}, 1000), "growth").state, "Unavailable", "no attribute yet")
		local badCoins: { any } = { 0 / 0, math.huge, "1000", -5 }
		for _, coins in badCoins do
			T.equal(UpgradesView.row(input(ZERO, coins), "growth").canBuy, false, tostring(coins))
		end
		T.equal(UpgradesView.row(input(ZERO, nil), "growth").canBuy, false, "no Coins attribute")
	end)

	test("row layout keeps the buy button at least 44 px on the smallest screens", function()
		local screens = {
			{ width = 667, height = 375, touch = true }, -- iPhone SE landscape
			{ width = 375, height = 667, touch = true }, -- portrait
			{ width = 1920, height = 1080, touch = false },
		}
		for _, screen in screens do
			local window = Layout.window(screen, Ui)
			local button = Layout.button(screen, Ui)
			local scale = Layout.scale(screen, Ui)
			local width = window.rect.width - 2 * window.padding
			local r = UpgradesView.layout(width, button, scale, Ui)
			local label = `{screen.width}x{screen.height}`
			T.isTrue(r.buy.width >= Ui.MinTouchTarget, `{label}: buy width {r.buy.width}`)
			T.isTrue(r.buy.height >= Ui.MinTouchTarget, `{label}: buy height {r.buy.height}`)
			T.isTrue(r.buy.x + r.buy.width <= width, `{label}: buy inside the row`)
			T.isTrue(r.effect.width > 0, `{label}: effect has room`)
			T.isTrue(r.name.x + r.name.width <= r.price.x, `{label}: name left of the price column`)
		end
	end)
end)

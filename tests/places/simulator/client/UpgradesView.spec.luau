--!strict
-- Upgrades window rows (#36 AC1, AC3, ADR 0010): level x/100, effect now -> after the next level,
-- the price with price rounding, the buy state, MAX at level 100 and "–" while not loaded. Row
-- layout keeps the 44 px floor on the smallest screens of ADR 0008.

local fs = require("@lune/fs")
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
		T.equal(rows.magnet.effectText, "4.0 studs", "locked: the current effect only")
		T.equal(rows.sellValue.effectText, "×1.00", "locked: the current effect only")
		T.equal(rows.stability.effectText, "10.00 → 9.92 % lost per hit")
	end)

	test("AC2: the price is the next level's formula price, shown with price rounding", function()
		local rows = byId(UpgradesView.rows(input(ZERO, 1000)))
		T.equal(rows.growth.priceText, "25")
		T.equal(rows.walkSpeed.priceText, "40")
		T.equal(rows.stability.priceText, "100")

		local levels = table.clone(ZERO)
		levels.growth = 30
		local row = UpgradesView.row(input(levels, 0), "growth")
		T.equal(row.priceText, E.NumberFormat.price(E.Upgrades.cost("growth", 31)))
		T.equal(row.levelText, "30/100")
	end)

	test("buy state follows the coins: Buy when affordable, greyed TooFewCoins otherwise", function()
		local rows = byId(UpgradesView.rows(input(ZERO, 100)))
		T.equal(rows.growth.state, "Buy")
		T.equal(rows.growth.canBuy, true)
		T.equal(rows.growth.buttonText, Ui.Text.UpgradeBuy)
		T.equal(rows.growth.missingText, nil)
		T.equal(rows.stability.state, "Buy", "exactly the price is enough")
		local poor = byId(UpgradesView.rows(input(ZERO, 30)))
		T.equal(poor.walkSpeed.state, "TooFewCoins")
		T.equal(poor.walkSpeed.canBuy, false)
		T.equal(poor.walkSpeed.buttonText, Ui.Text.UpgradeBuy, "same label, greyed")
	end)

	test("R1-2: the missing amount is price - Coins from the same price as the shown price", function()
		local poor = byId(UpgradesView.rows(input(ZERO, 30)))
		T.equal(poor.walkSpeed.missing, 10)
		T.equal(poor.walkSpeed.missingText, "Need 10 more")
		T.equal(poor.stability.missing, 70)
		T.equal(poor.stability.missingText, "Need 70 more")
		T.equal(poor.growth.state, "Buy")

		-- Large amounts use price rounding (up), so the message never understates what is missing.
		local levels = table.clone(ZERO)
		levels.growth = 20
		local price = E.Upgrades.cost("growth", 21)
		local coins = price - 1_150
		local row = UpgradesView.row(input(levels, coins), "growth")
		T.equal(row.priceText, E.NumberFormat.price(price), "shown price")
		T.equal(row.missing, 1_150)
		T.equal(row.missingText, "Need 1.2K more", "1,150 rounds up to 1.2K, not down to 1.1K")
		local high = table.clone(ZERO)
		high.growth = 60
		local highPrice = E.Upgrades.cost("growth", 61)
		T.isTrue(highPrice > 3_755_901, "level 61 costs more than every shortfall below")
		for _, shortfall in { 1, 999, 1_001, 1_234_567, 3_755_901 } do
			local r = UpgradesView.row(input(high, highPrice - shortfall), "growth")
			T.equal(r.missing, shortfall)
			T.equal(r.missingText, UpgradesView.missingText(Ui.Text.UpgradeNeedMore, E.NumberFormat.price(shortfall)))
		end
		T.equal(UpgradesView.missingText("Need {amount} more", "3.8M"), "Need 3.8M more")
		T.equal(UpgradesView.missingText("{amount}", "50%"), "50%", "a % in the amount is kept")
	end)

	test("R1-1: Magnet and Sell value are visible, locked and marked Coming soon", function()
		T.equal(Upgrades.Locked.magnet, true)
		T.equal(Upgrades.Locked.sellValue, true)
		for _, coins in { 0, 1e30 } do
			local rows = byId(UpgradesView.rows(input(ZERO, coins)))
			for _, id in { "magnet", "sellValue" } do
				local row = rows[id]
				T.equal(row.state, "Locked", id)
				T.equal(row.canBuy, false, `{id} never buyable`)
				T.equal(row.priceText, Ui.Text.UpgradeComingSoon)
				T.equal(row.priceText, "Coming soon")
				T.equal(row.missingText, nil)
				T.equal(row.name, Ui.UpgradeRows[id].Name, "still listed by name")
				T.equal(row.levelText, "0/100")
			end
			for _, id in { "growth", "walkSpeed", "stability" } do
				T.isTrue(rows[id].state ~= "Locked", `{id} is not locked`)
			end
		end
		local notLoaded = UpgradesView.row(input(ZERO, 1000, "Loading"), "magnet")
		T.equal(notLoaded.state, "Locked", "locked also while loading")
		T.equal(notLoaded.levelText, Ui.Text.Missing)
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

	test("R1-2: the panel fires the remote only for a buyable row; a greyed tap shows MissingAmount", function()
		local panel = fs.readFile("src/places/simulator/client/SimulatorHudController/UpgradesPanel.luau")
		T.isTrue(
			string.find(panel, "if row.canBuy then\n\t\t\t\tif remote then\n\t\t\t\t\tremote:FireServer(id)", 1, true)
				~= nil,
			"FireServer only inside the canBuy branch"
		)
		T.isTrue(string.find(panel, 'elseif row.state == "TooFewCoins" and row.missingText then', 1, true) ~= nil)
		T.isTrue(string.find(panel, '"MissingAmount"', 1, true) ~= nil, "named label for playtests")
		T.isTrue(string.find(panel, "Ui.UpgradesWindow.MissingMessageSeconds", 1, true) ~= nil, "duration from config")
		T.isTrue(string.find(panel, 'view.buy:SetAttribute("State", row.state)', 1, true) ~= nil, "state readable")
		T.equal(Ui.UpgradesWindow.MissingMessageSeconds, 2)
		T.equal(Ui.Text.UpgradeNeedMore, "Need {amount} more")
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

--!strict
-- ZoneView (#39): the unlock window with enough coins and the missing amount with too few
-- (AC2), nothing at a closed barrier (AC7), the label texts and the zone teleport list of only
-- unlocked zones (AC4). Real Config.Ui texts, Config.Zones names and formulas.

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local UiConfig = require("../../../../src/shared/Config/Ui")
local ZoneAttributes = require("../../../../src/shared/ZoneAttributes")
local ZoneView = require("../../../../src/places/simulator/client/ZoneController/ZoneView")

local Text = UiConfig.Text

local function facts(overrides: { [string]: any }?): ZoneView.WalkInFacts
	local base: any = {
		loaded = true,
		unlocked = { [1] = true },
		barrierZone = 1,
		canOpen = true,
		coins = 1000,
		price = E.Zones.barrierPrice(1),
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

local function decode(value: any)
	return ZoneAttributes.decode(value, E.Zones.isZone)
end

return T.suite("ZoneView (#39)", function(test)
	test("AC2: enough coins opens the window, too few shows the missing amount", function()
		T.equal(ZoneView.walkIn(facts({ coins = 320 })), "Window", "exactly the price is enough")
		local action, missing = ZoneView.walkIn(facts({ coins = 100 }))
		T.equal(action, "NeedMore")
		T.equal(missing, 220)
	end)

	test("AC7: a closed barrier shows no window and no missing amount", function()
		T.equal(ZoneView.walkIn(facts({ canOpen = false, coins = 1e12 })), "None")
		T.equal(ZoneView.walkIn(facts({ canOpen = false, coins = 0 })), "None")
		T.equal(ZoneView.canBuy(facts({ canOpen = false })), false, "and no prompt")
		T.equal(
			ZoneView.barrierLabel(5, false, { [1] = true }, Text, "30K"),
			"Zone 6 · Coming soon",
			"visible, closed label"
		)
	end)

	test("nothing for an open, a far or an unknown barrier", function()
		T.equal(ZoneView.walkIn(facts({ unlocked = { [1] = true, [2] = true } })), "None", "already open")
		T.equal(ZoneView.walkIn(facts({ barrierZone = 2 })), "None", "zone 2 itself is not unlocked")
		T.equal(ZoneView.walkIn(facts({ loaded = false })), "None", "not loaded")
		local noList: any = facts()
		noList.unlocked = nil
		T.equal(ZoneView.walkIn(noList), "None", "no unlocked list")
		local noCoins: any = facts()
		noCoins.coins = nil
		T.equal(ZoneView.walkIn(noCoins), "None", "no Coins attribute")
		for _, coins in { "1000", 0 / 0, math.huge, -1 } :: { any } do
			T.equal(ZoneView.walkIn(facts({ coins = coins })), "None", tostring(coins))
		end
	end)

	test("label: 'Zone N · price' until this player opened it", function()
		T.equal(ZoneView.barrierLabel(1, true, { [1] = true }, Text, "320"), "Zone 2 · 320")
		T.equal(ZoneView.barrierLabel(1, true, { [1] = true, [2] = true }, Text, "320"), nil)
		T.equal(ZoneView.barrierLabel(1, true, nil, Text, "320"), "Zone 2 · 320", "price shown while loading")
	end)

	test("window question: 'Unlock Zone N for X?'", function()
		T.equal(ZoneView.question(6, "3.7M", Text), "Unlock Zone 6 for 3.7M?")
	end)

	test("AC4: the teleport list holds only unlocked zones, with their names", function()
		local rows = ZoneView.teleportRows("Loaded", "1,3,2", decode, E.Zones.worldOf, 1, E.Config.Zones.Names, Text)
		T.equal(#(rows :: { any }), 3)
		local list = rows :: { ZoneView.Row }
		T.equal(list[1].text, "Zone 1 · Snowline")
		T.equal(list[2].zone, 2)
		T.equal(list[3].text, "Zone 3 · Alpine Hut")
		local one = ZoneView.teleportRows("Loaded", "1", decode, E.Zones.worldOf, 1, E.Config.Zones.Names, Text)
		T.equal(#(one :: { any }), 1, "a new player: zone 1 only")
	end)

	test("AC4: zones of other worlds are not listed here", function()
		local rows = ZoneView.teleportRows("Loaded", "1,2,11", decode, E.Zones.worldOf, 1, E.Config.Zones.Names, Text)
		T.equal(#(rows :: { any }), 2)
	end)

	test("AC4: nothing is listed while not loaded or with a broken attribute", function()
		for _, status in { "Loading", "Failed", nil } :: { any } do
			T.equal(ZoneView.teleportRows(status, "1,2", decode, E.Zones.worldOf, 1, E.Config.Zones.Names, Text), nil)
		end
		for _, value in { nil, "", "1,x", "1,,2", "1.5", 1, "0", "51" } :: { any } do
			T.equal(
				ZoneView.teleportRows("Loaded", value, decode, E.Zones.worldOf, 1, E.Config.Zones.Names, Text),
				nil,
				tostring(value)
			)
		end
	end)
end)

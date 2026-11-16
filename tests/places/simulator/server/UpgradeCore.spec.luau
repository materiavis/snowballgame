--!strict
-- UpgradeCore (#36, ADR 0010): the purchase decision with the real Config.Upgrades, the real
-- Formulas.Upgrades and the real CurrencyCore on an in-memory profile. AC2 (formula, level 100
-- is the maximum), AC6 (no client value trusted: id checked, level and price from the server).

local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local CurrencyConfig = require("../../../../src/shared/Config/Currency")
local CurrencyCore = require("../../../../src/server/Services/CurrencyService/CurrencyCore")
local UpgradeCore = require("../../../../src/places/simulator/server/UpgradeService/UpgradeCore")
local UpgradeAttributes = require("../../../../src/shared/UpgradeAttributes")

local USER = 7
local Upgrades = E.Config.Upgrades

type World = {
	profile: any,
	loaded: boolean,
	currency: any,
	core: UpgradeCore.Core,
	events: { UpgradeCore.Event },
}

local function newProfile(): any
	return {
		sim = {
			coins = 0,
			totalCoins = 0,
			upgrades = { growth = 0, walkSpeed = 0, magnet = 0, sellValue = 0, stability = 0 },
		},
		fight = { snowCoins = 0 },
	}
end

local function world(): World
	local w = { profile = newProfile(), loaded = true, events = {} } :: any
	local function getProfile(userId: number): any
		if userId == USER and w.loaded then
			return w.profile
		end
		return nil
	end
	w.currency = CurrencyCore.new({ config = CurrencyConfig :: any, getProfile = getProfile, log = function() end })
	w.core = UpgradeCore.new({
		config = Upgrades :: any,
		formulas = E.Upgrades,
		getProfile = getProfile,
		spendCoins = function(userId: number, amount: number, reason: string)
			return w.currency.spend(userId, "Coins", amount, reason)
		end,
		log = function() end,
	})
	w.core.subscribe(function(event)
		table.insert(w.events, event)
	end)
	return w
end

local function give(w: World, coins: number)
	assert(w.currency.add(USER, "Coins", coins, "Test"))
end

return T.suite("UpgradeService.UpgradeCore (7.8)", function(test)
	test("all five upgrades exist, in the save format's ids, with MaxLevel 100", function()
		local w = world()
		T.equal(table.concat(w.core.ids(), ","), "growth,walkSpeed,magnet,sellValue,stability")
		T.equal(Upgrades.MaxLevel, 100)
		for _, id in w.core.ids() do
			T.isTrue(w.core.isUpgrade(id), id)
			T.equal(w.core.level(USER, id), 0, `{id} starts at 0`)
		end
	end)

	test("AC2: a purchase costs BasePrice * Factor^(level - 1), rounded down, from the server's level", function()
		for _, id in { "growth", "walkSpeed", "stability" } do
			local w = world()
			local def = Upgrades.Definitions[id]
			for level = 1, 5 do
				local expected = math.floor(def.BasePrice * def.Factor ^ (level - 1) * (1 + 1e-12))
				T.equal(w.core.nextPrice(USER, id), expected, `{id} price of level {level}`)
				give(w, expected)
				local ok, newLevel = w.core.purchase(USER, id, "Remote")
				T.equal(ok, true, `{id} level {level} bought`)
				T.equal(newLevel, level)
				T.equal(w.currency.get(USER, "Coins"), 0, `{id} level {level} took exactly the price`)
				local event = w.events[#w.events]
				T.equal(event.kind, "Purchase")
				T.equal(event.price, expected)
				T.equal(event.from, level - 1)
				T.equal(event.to, level)
			end
			T.equal(w.profile.sim.upgrades[id], 5)
		end
	end)

	test("AC2: the shipped first prices are the concept 7.8 base prices", function()
		local w = world()
		T.equal(w.core.nextPrice(USER, "growth"), 25)
		T.equal(w.core.nextPrice(USER, "walkSpeed"), 40)
		T.equal(w.core.nextPrice(USER, "magnet"), 150)
		T.equal(w.core.nextPrice(USER, "sellValue"), 200)
		T.equal(w.core.nextPrice(USER, "stability"), 100)
	end)

	test("AC2: level 100 is the maximum; buying past it is refused and costs nothing", function()
		local w = world()
		w.profile.sim.upgrades.walkSpeed = 99
		local price = E.Upgrades.cost("walkSpeed", 100)
		give(w, price + 5)
		T.equal(w.core.nextPrice(USER, "walkSpeed"), price)
		T.equal(w.core.purchase(USER, "walkSpeed", "Remote"), true)
		T.equal(w.core.level(USER, "walkSpeed"), 100)
		T.equal(w.core.nextPrice(USER, "walkSpeed"), nil, "no price at the maximum")

		local ok, refusal = w.core.purchase(USER, "walkSpeed", "Remote")
		T.equal(ok, false)
		T.equal(refusal, "MaxLevel")
		T.equal(w.core.level(USER, "walkSpeed"), 100)
		T.equal(w.currency.get(USER, "Coins"), 5, "nothing charged")
		T.equal(E.Upgrades.effect("walkSpeed", 100), 32, "end value 32 studs/s at level 100")
	end)

	test("R1-1: Magnet and Sell value are refused with Locked before any coin spend", function()
		local w = world()
		local spends = 0
		local unsubscribe = w.currency.subscribe(function()
			spends += 1
		end)
		give(w, 1e9)
		spends = 0
		for _, id in { "magnet", "sellValue" } do
			T.isTrue(w.core.isLocked(id), `{id} locked`)
			local ok, refusal = w.core.purchase(USER, id, "Remote")
			T.equal(ok, false, id)
			T.equal(refusal, "Locked", id)
			T.equal(UpgradeCore.Refusal.Locked, "Locked")
			T.equal(w.core.level(USER, id), 0, `{id} level unchanged`)
			local event = w.events[#w.events]
			T.equal(event.kind, "Refused")
			T.equal(event.refusal, "Locked")
			T.equal(event.price, nil, "no price was even computed")
		end
		T.equal(w.currency.get(USER, "Coins"), 1e9, "nothing charged")
		T.equal(spends, 0, "CurrencyCore was never asked to spend")
		unsubscribe()
		for _, id in { "growth", "walkSpeed", "stability" } do
			T.equal(w.core.isLocked(id), false, `{id} buyable`)
		end
		-- Locked wins over not loaded and over a broken stored level: it is checked first.
		w.loaded = false
		T.equal(select(2, w.core.purchase(USER, "magnet", "Remote")), "Locked")
	end)

	test("R1-1: the lock comes from Config.Upgrades.Locked, the same table the client reads", function()
		T.equal(Upgrades.Locked.magnet, true)
		T.equal(Upgrades.Locked.sellValue, true)
		T.equal(Upgrades.Locked.growth, nil)
		T.isTrue(table.isfrozen(Upgrades.Locked))
		-- Without a Locked table nothing is locked (what #38/#40 return to).
		local open = UpgradeCore.new({
			config = { MaxLevel = Upgrades.MaxLevel, Order = Upgrades.Order, Definitions = Upgrades.Definitions },
			formulas = E.Upgrades,
			getProfile = function()
				return newProfile()
			end,
			spendCoins = function()
				return true
			end,
			log = function() end,
		})
		T.equal(open.isLocked("magnet"), false)
		T.equal(open.purchase(USER, "magnet", "Remote"), true)
	end)

	test("R1-1: UpgradeSetLevel may still set a locked upgrade (saving and the #38/#40 seam)", function()
		local w = world()
		T.equal(w.core.setLevel(USER, "sellValue", 40, "StudioSwitch"), true)
		T.equal(w.core.levelOrZero(USER, "sellValue"), 40)
		T.equal(select(2, w.core.purchase(USER, "sellValue", "Remote")), "Locked", "still not buyable")
	end)

	test("insufficient coins: refused, level and balance unchanged", function()
		local w = world()
		give(w, 24)
		local ok, refusal = w.core.purchase(USER, "growth", "Remote")
		T.equal(ok, false)
		T.equal(refusal, "Insufficient")
		T.equal(w.core.level(USER, "growth"), 0)
		T.equal(w.currency.get(USER, "Coins"), 24)
		local event = w.events[#w.events]
		T.equal(event.kind, "Refused")
		T.equal(event.price, 25)
	end)

	test("AC6: an unknown or malformed id is refused before anything is read or spent", function()
		local w = world()
		give(w, 1000)
		local bads: { any } = { "speed", "", "Growth", 1, true, {}, "growth ", "__index" }
		for _, bad in bads do
			local ok, refusal = w.core.purchase(USER, bad, "Remote")
			T.equal(ok, false, `{tostring(bad)} refused`)
			T.equal(refusal, "BadId", `{tostring(bad)} is BadId`)
		end
		T.equal(select(2, w.core.purchase(USER, nil, "Remote")), "BadId", "nil is BadId")
		T.equal(w.currency.get(USER, "Coins"), 1000)
	end)

	test("not loaded: refused with NotLoaded, nothing changes", function()
		local w = world()
		give(w, 1000)
		w.loaded = false
		T.equal(select(2, w.core.purchase(USER, "growth", "Remote")), "NotLoaded")
		w.loaded = true
		T.equal(w.core.level(USER, "growth"), 0)
		T.equal(w.currency.get(USER, "Coins"), 1000)
	end)

	test("a broken stored level is never bought on; effects read it as 0", function()
		for _, broken in { -1, 101, 2.5, 0 / 0, "3", math.huge } do
			local w = world()
			give(w, 1000)
			w.profile.sim.upgrades.stability = broken
			T.equal(select(2, w.core.purchase(USER, "stability", "Remote")), "BadProfile", `{tostring(broken)}`)
			T.equal(w.currency.get(USER, "Coins"), 1000, `{tostring(broken)}: nothing charged`)
			T.equal(w.core.levelOrZero(USER, "stability"), 0)
			T.equal(w.core.nextPrice(USER, "stability"), nil)
		end
	end)

	test("levelOrZero is 0 while not loaded and errors on an unknown id", function()
		local w = world()
		w.profile.sim.upgrades.growth = 30
		T.equal(w.core.levelOrZero(USER, "growth"), 30)
		w.loaded = false
		T.equal(w.core.levelOrZero(USER, "growth"), 0)
		T.throws(function()
			w.core.levelOrZero(USER, "speed")
		end, "unknown upgrade")
	end)

	test("setLevel (Studio switch) uses the same id, level and profile checks and spends nothing", function()
		local w = world()
		T.equal(w.core.setLevel(USER, "stability", 100, "StudioSwitch"), true)
		T.equal(w.core.level(USER, "stability"), 100)
		T.equal(w.events[#w.events].kind, "Set")
		for _, bad in { -1, 101, 1.5, 0 / 0, "x", math.huge } do
			T.equal(select(2, w.core.setLevel(USER, "stability", bad, "StudioSwitch")), "BadLevel", tostring(bad))
		end
		T.equal(select(2, w.core.setLevel(USER, "nope", 3, "StudioSwitch")), "BadId")
		w.loaded = false
		T.equal(select(2, w.core.setLevel(USER, "growth", 3, "StudioSwitch")), "NotLoaded")
		w.loaded = true
		T.equal(w.core.level(USER, "stability"), 100)
		T.equal(w.currency.get(USER, "Coins"), 0)
	end)

	test("parseSetLevel reads '<id> <level>' and passes bad levels on to be refused", function()
		local id, level = UpgradeCore.parseSetLevel("walkSpeed 100")
		T.equal(id, "walkSpeed")
		T.equal(level, 100)
		id, level = UpgradeCore.parseSetLevel("  growth   1.5 ")
		T.equal(id, "growth")
		T.equal(level, 1.5)
		id, level = UpgradeCore.parseSetLevel("growth max")
		T.equal(level, "max")
		T.equal((UpgradeCore.parseSetLevel("growth")), nil)
		T.equal((UpgradeCore.parseSetLevel(5)), nil)
	end)

	test("a failing listener does not undo a purchase", function()
		local w = world()
		w.core.subscribe(function()
			error("analytics down")
		end)
		give(w, 25)
		T.equal(w.core.purchase(USER, "growth", "Remote"), true)
		T.equal(w.core.level(USER, "growth"), 1)
	end)

	test("attribute names", function()
		T.equal(UpgradeAttributes.level("walkSpeed"), "UpgradeWalkSpeedLevel")
		T.equal(UpgradeAttributes.level("growth"), "UpgradeGrowthLevel")
		T.equal(UpgradeAttributes.effect("sellValue"), "UpgradeSellValueEffect")
	end)
end)

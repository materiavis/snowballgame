--!strict
-- Save format v1 defaults (ADR 0003 data model) and preparing stored profiles.

local T = require("../../TestKit")
local H = require("./Harness")
local FakeStore = require("../../../src/server/Services/DataService/FakeStore")

return T.suite("DataService/Schema", function(test)
	test("v1 defaults hold every top-level field of the ADR 0003 table", function()
		local profile = H.Schema.newProfile()
		T.equal(H.Schema.VERSION, 1)
		T.equal(profile.schemaVersion, 1)
		for _, key in { "settings", "tutorial", "groupChestClaimed", "lastMode", "boosts", "sim", "fight", "purchases" } do
			T.isTrue(profile[key] ~= nil, key)
		end
		for _, key in
			{
				"coins",
				"totalCoins",
				"upgrades",
				"unlockedZones",
				"lastWorld",
				"lastZone",
				"highestZone",
				"rebirths",
				"pets",
				"inventorySize",
				"collection",
				"records",
				"titles",
				"stats",
				"daily",
				"ballSkins",
				"starterPackBought",
				"tradeHistory",
				"pendingTradeId",
			}
		do
			T.isTrue(profile.sim[key] ~= nil, `sim.{key}`)
		end
		T.equal(profile.sim.inventorySize, H.Config.InventorySize)
		T.equal(profile.sim.pendingTradeId, "")
		T.isTrue(profile.sim.collection.finds ~= nil, "collection finds stored from launch")
		T.equal(profile.purchases.receipts ~= nil, true)
	end)

	test("each call returns a fresh table", function()
		local a, b = H.Schema.newProfile(), H.Schema.newProfile()
		a.sim.coins = 5
		T.equal(b.sim.coins, 0)
	end)

	test("defaults can be stored in a DataStore", function()
		FakeStore.checkSavable(H.Schema.newProfile())
	end)

	test("prepare fills missing fields and keeps stored values and map entries", function()
		local stored = H.Schema.newProfile()
		stored.sim.coins = 77
		stored.sim.pets = { p1 = { kind = "Penguin", variant = "normal", frosty = false, equipped = true } }
		stored.sim.upgrades.growth = nil
		stored.fight = nil
		local data = H.Schema.prepare(stored)
		T.equal(data.sim.coins, 77)
		T.equal(data.sim.pets.p1.kind, "Penguin")
		T.equal(data.sim.upgrades.growth, 0)
		T.equal(data.fight.level, 1)
		T.equal(data.sim.pets.default, nil, "maps are not filled")
	end)

	test("prepare refuses what it cannot use", function()
		T.equal((H.Schema.prepare(nil)), nil)
		T.equal((H.Schema.prepare({})), nil, "no version")
		T.equal((H.Schema.prepare({ schemaVersion = 0.5 })), nil)
		local data, reason = H.Schema.prepare({ schemaVersion = 2 })
		T.equal(data, nil)
		T.isTrue(string.find(reason :: string, "newer") ~= nil, reason)
	end)
end)

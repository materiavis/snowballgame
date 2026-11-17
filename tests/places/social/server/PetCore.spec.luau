--!strict
-- PetCore rules (#41 AC1, AC8, ADR 0013): adding pets with unique uids, the inventory limit,
-- equipping within Formulas.Pets.equipSlots, the additive multiplier (x1.4 + x2.0 + x3.0 = x4.4
-- through the equip path), and that no client value is trusted. Also the attribute mirror.

local T = require("../../../TestKit")
local P = require("../../../helpers/Pets")
local DataConfig = require("../../../../src/shared/Config/Data")
local PetsConfig = require("../../../../src/shared/Config/Pets")
local Schema = require("../../../../src/server/Services/DataService/Schema")
local PetAttributes = require("../../../../src/places/social/server/PetService/PetAttributes")
local PetCodec = require("../../../../src/shared/PetCodec")

local USER = 1001
local schema = Schema.new(DataConfig)

local function setup(options: any?): (any, P.Game)
	local profile = schema.newProfile()
	local game = P.on(function(userId: number): any
		return if userId == USER then profile else nil
	end, options)
	return profile, game
end

local function fakePlayer(): any
	local attributes: { [string]: any } = {}
	return {
		attributes = attributes,
		SetAttribute = function(_self: any, name: string, value: any)
			attributes[name] = value
		end,
	}
end

return T.suite("PetCore (7.9, ADR 0013)", function(test)
	test("add stores { kind, variant, frosty, equipped } under a unique uid", function()
		local profile, game = setup()
		local ok, uid = game.pets.add(USER, "SnowHare", "Egg:1")
		T.isTrue(ok)
		local record = profile.sim.pets[uid]
		T.equal(record.kind, "SnowHare")
		T.equal(record.variant, "normal")
		T.equal(record.frosty, false)
		T.equal(record.equipped, false)
		local _, second = game.pets.add(USER, "SnowHare", "Egg:1")
		T.isTrue(second ~= uid, "every pet has its own uid")
		T.equal(game.pets.count(USER), 2)
		T.equal(game.petEvents[1].kind, "Added")
	end)

	test("a uid clash asks for a new uid; unknown kinds are refused", function()
		local profile, game = setup()
		profile.sim.pets["1001_6553f100_0001"] =
			{ kind = "SnowHare", variant = "normal", frosty = false, equipped = false }
		local ok, uid = game.pets.add(USER, "Marmot", "Test")
		T.isTrue(ok)
		T.equal(uid, "1001_6553f100_0002", "the taken candidate was skipped")
		T.equal(select(2, game.pets.add(USER, "Dragon", "Test")), "BadKind")
		T.equal(select(2, game.pets.add(USER, nil, "Test")), "BadKind")
	end)

	test("the inventory limit is sim.inventorySize (Config.Data.InventorySize = 50)", function()
		local profile, game = setup()
		T.equal(game.pets.capacity(USER), 50)
		for _ = 1, 50 do
			T.isTrue((game.pets.add(USER, "SnowHare", "Test")))
		end
		T.equal(select(2, game.pets.hasRoom(USER)), "InventoryFull")
		T.equal(select(2, game.pets.add(USER, "SnowHare", "Test")), "InventoryFull")
		T.equal(game.pets.count(USER), 50)
		profile.sim.inventorySize = "lots"
		T.equal(game.pets.capacity(USER), DataConfig.InventorySize, "a broken stored size falls back to the default")
	end)

	test("not loaded or broken profiles are refused", function()
		local game = P.on(function()
			return nil
		end)
		T.equal(select(2, game.pets.add(USER, "SnowHare", "Test")), "NotLoaded")
		T.equal(select(2, game.pets.setEquipped(USER, "x", true, "Remote")), "NotLoaded")
		T.equal(game.pets.multiplier(USER), 1, "x1 while not loaded")
		T.equal(game.pets.entries(USER), nil)
		local profile, broken = setup()
		profile.sim.pets = "nope"
		T.equal(select(2, broken.pets.add(USER, "SnowHare", "Test")), "BadProfile")
	end)

	test("equip within the slots: 3 at the start, +1 at zone 10, +3 with the pass", function()
		local profile, game = setup()
		local uids = {}
		for index = 1, 5 do
			uids[index] = select(2, game.pets.add(USER, "SnowHare", "Test"))
		end
		T.equal(game.pets.slots(USER), 3)
		for index = 1, 3 do
			T.isTrue((game.pets.setEquipped(USER, uids[index], true, "Remote")))
		end
		T.equal(select(2, game.pets.setEquipped(USER, uids[4], true, "Remote")), "SlotsFull")
		T.equal(profile.sim.pets[uids[4]].equipped, false, "a refusal changes nothing")
		T.equal(select(2, game.pets.setEquipped(USER, uids[1], true, "Remote")), "Unchanged")
		T.isTrue((game.pets.setEquipped(USER, uids[1], false, "Remote")))
		T.isTrue((game.pets.setEquipped(USER, uids[4], true, "Remote")), "a freed slot can be used")
		profile.sim.highestZone = 10
		T.equal(game.pets.slots(USER), 4)
		local _, withPass = setup({ slotsPass = true })
		T.equal(withPass.pets.slots(USER), 6)
	end)

	test("AC8: the client's uid and state are checked, never trusted", function()
		local profile, game = setup()
		local _, uid = game.pets.add(USER, "SnowHare", "Test")
		T.equal(select(2, game.pets.setEquipped(USER, "someone_elses_pet", true, "Remote")), "BadUid")
		T.equal(select(2, game.pets.setEquipped(USER, 42, true, "Remote")), "BadUid")
		T.equal(select(2, game.pets.setEquipped(USER, uid, "yes", "Remote")), "BadState")
		profile.sim.pets.broken = { kind = "Dragon", equipped = false }
		T.equal(select(2, game.pets.setEquipped(USER, "broken", true, "Remote")), "BadPet")
		T.equal(game.pets.multiplier(USER), 1)
	end)

	test("AC1: equipped bonuses add up, x1.4 + x2.0 + x3.0 = x4.4, through equip", function()
		-- Bonus = multiplier - 1, as in Formulas.Pets: three pets with 0.4, 1.0 and 2.0.
		local bonuses = { SnowHare = 0.4, AlpineChough = 1.0, Marmot = 2.0 }
		local _, game = setup({
			bonusOf = function(record: any): number?
				return if type(record) == "table" then bonuses[record.kind] else nil
			end,
		})
		local uids = {}
		for _, kind in { "SnowHare", "AlpineChough", "Marmot" } do
			local _, uid = game.pets.add(USER, kind, "Test")
			table.insert(uids, uid)
		end
		T.equal(game.pets.multiplier(USER), 1, "nothing equipped: x1")
		for _, uid in uids do
			game.pets.setEquipped(USER, uid, true, "Remote")
		end
		T.near(game.pets.multiplier(USER), 4.4, 1e-12)
	end)

	test("Egg 1 pets: Snow Hare + Red Fox + Snowy Owl = x2.15 with the shipped bonuses", function()
		local _, game = setup()
		for _, kind in { "SnowHare", "RedFox", "SnowyOwl" } do
			local _, uid = game.pets.add(USER, kind, "Test")
			game.pets.setEquipped(USER, uid, true, "Remote")
		end
		T.near(game.pets.multiplier(USER), 1 + 0.1 + 0.35 + 0.7, 1e-12)
	end)

	test("more equipped than slots in a stored profile: only the strongest count", function()
		local profile, game = setup()
		for index, kind in { "SnowHare", "AlpineChough", "Marmot", "RedFox" } do
			profile.sim.pets[`p{index}`] = { kind = kind, variant = "normal", frosty = false, equipped = true }
		end
		T.near(game.pets.multiplier(USER), 1 + 0.15 + 0.22 + 0.35, 1e-12)
		T.equal(select(2, game.pets.setEquipped(USER, "p1", true, "Remote")), "Unchanged")
		T.isTrue((game.pets.setEquipped(USER, "p1", false, "Remote")), "unequipping is always allowed")
	end)

	test("clear empties the inventory (Studio switch PetClear)", function()
		local profile, game = setup()
		game.pets.add(USER, "SnowHare", "Test")
		game.pets.add(USER, "RedFox", "Test")
		local ok, removed = game.pets.clear(USER, "StudioSwitch")
		T.isTrue(ok)
		T.equal(removed, 2)
		T.equal(next(profile.sim.pets), nil)
	end)

	test("PetAttributes writes multiplier, slots, size, inventory and equipped", function()
		local _, game = setup()
		local _, hare = game.pets.add(USER, "SnowHare", "Test")
		local _, fox = game.pets.add(USER, "RedFox", "Test")
		game.pets.setEquipped(USER, fox, true, "Remote")
		local function build(diagnostics: boolean)
			return PetAttributes.new({
				multiplierName = PetsConfig.MultiplierAttribute,
				names = PetsConfig.Attributes,
				entries = game.pets.entries,
				multiplier = game.pets.multiplier,
				slots = game.pets.slots,
				capacity = game.pets.capacity,
				count = game.pets.count,
				encodeInventory = PetCodec.encodeInventory,
				encodeEquipped = PetCodec.encodeEquipped,
				diagnostics = diagnostics,
			})
		end
		local player = fakePlayer()
		T.isTrue(build(false).mirror(player, USER))
		local a = player.attributes
		T.equal(PetsConfig.MultiplierAttribute, "PetMultiplier", "the name #38 reads")
		T.near(a.PetMultiplier, 1.35, 1e-12)
		T.equal(a.PetSlots, 3)
		T.equal(a.PetInventorySize, 50)
		T.equal(a.PetInventory, `{hare}:SnowHare:0;{fox}:RedFox:1`)
		T.equal(a.PetEquipped, `{fox}:RedFox`)
		T.equal(a.PetInventoryCount, nil, "no diagnostics on live servers")
		local studio = fakePlayer()
		build(true).mirror(studio, USER)
		T.equal(studio.attributes.PetInventoryCount, 2)
		T.equal(studio.attributes.PetEquippedUids, fox)
		T.equal(build(false).mirror(fakePlayer(), 999), false, "not loaded: nothing written")
	end)
end)

--!strict
-- Pets and eggs against DataService and the fake store (#41 AC11, concept 6.5): a hatched pet and
-- its equip state land with the next save, survive a forced save failure and a rejoin, and never
-- reach the store without the coins they cost. The cores read profiles through
-- DataCore.getData, exactly as PetService and EggService do through DataService.GetProfile.

local T = require("../../../TestKit")
local H = require("../../../server/DataService/Harness")
local P = require("../../../helpers/Pets")

local USER = H.USER

local function gameOn(server: H.Server): P.Game
	return P.on(function(userId: number): any
		return server.core.getData(userId)
	end)
end

local function stored(world: H.World): (number?, any)
	local record = H.stored(world, USER)
	if record == nil then
		return nil, nil
	end
	return record.data.sim.coins, record.data.sim.pets
end

local function count(pets: any): number
	local n = 0
	for _ in pets do
		n += 1
	end
	return n
end

return T.suite("Pets and eggs save rules (6.5, ADR 0013)", function(test)
	test("AC11: a hatched, equipped pet survives a failed save, a later save and a rejoin", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", 300, "Sell")
		server.core.autosaveAll()

		local ok, uid = g.eggs.purchase(USER, 1, "Remote")
		T.isTrue(ok)
		T.isTrue((g.pets.setEquipped(USER, uid, true, "Remote")))
		local multiplier = g.pets.multiplier(USER)
		T.isTrue(multiplier > 1)

		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.save(USER, "Autosave"), false, "forced save failure (DataFailSave)")
		local coins, pets = stored(world)
		T.equal(coins, 300, "the store keeps the old balance")
		T.equal(count(pets), 0, "and no pet: neither half was written")
		T.equal(g.currency.get(USER, "Coins"), 60, "the spend stays on the server")
		T.equal(server.core.getData(USER).sim.pets[uid].equipped, true, "the pet and its state stay on the server")

		world.store:setFailing("UpdateAsync", false)
		T.equal(server.core.save(USER, "Autosave"), true)
		coins, pets = stored(world)
		T.equal(coins, 60, "the next save stores the spend")
		T.equal(pets[uid].kind, server.core.getData(USER).sim.pets[uid].kind, "together with the pet")
		T.equal(pets[uid].equipped, true, "and its equip state")

		-- Rejoin (DataSimulateRejoin releases and loads again).
		T.equal(server.core.release(USER, "Leave"), true)
		local again = H.server(world, "B")
		again.core.load(USER)
		local g2 = gameOn(again)
		local entries = g2.pets.entries(USER) :: any
		T.equal(#entries, 1)
		T.equal(entries[1].uid, uid)
		T.equal(entries[1].equipped, true)
		T.near(g2.pets.multiplier(USER), multiplier, 1e-12, "PetMultiplier is the same after the rejoin")
		T.equal(g2.currency.get(USER, "Coins"), 60)
	end)

	test("AC11: a save failure on leave keeps the lock; autosave stores pet and spend later", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", 240, "Sell")
		local _, uid = g.eggs.purchase(USER, 1, "Remote")
		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.release(USER, "Leave"), false)
		world.store:setFailing("UpdateAsync", false)
		server.core.autosaveAll()
		local coins, pets = stored(world)
		T.equal(coins, 0)
		T.isTrue(pets[uid] ~= nil)
	end)

	test("AC11 6.5: a double tap stores one pet and one price", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		g.currency.add(USER, "Coins", 480, "Sell")
		g.eggs.purchase(USER, 1, "Remote")
		T.equal(select(2, g.eggs.purchase(USER, 1, "Remote")), "Busy")
		server.core.autosaveAll()
		local coins, pets = stored(world)
		T.equal(coins, 240)
		T.equal(count(pets), 1)
	end)

	test("6.5 Laden: hatching or equipping while the profile is not loaded writes nothing", function()
		local world = H.world()
		local seed = H.server(world, "seed")
		local seeded = gameOn(seed)
		seed.core.load(USER)
		seeded.currency.add(USER, "Coins", 500, "Sell")
		seed.core.release(USER, "Leave")
		local before = H.stored(world, USER)

		world.store:setFailing("UpdateAsync", true)
		local server = H.server(world, "B")
		local g = gameOn(server)
		local hatch: string? = nil
		local equip: string? = nil
		server.onWait = function()
			if server.core.getStatus(USER) == "Failed" and hatch == nil then
				hatch = select(2, g.eggs.purchase(USER, 1, "Remote"))
				equip = select(2, g.pets.setEquipped(USER, "any", true, "Remote"))
				world.store:setFailing("UpdateAsync", false)
			end
		end
		T.equal(server.core.load(USER), "Loaded")
		T.equal(hatch, "NotLoaded")
		T.equal(equip, "NotLoaded")
		T.equal(g.currency.get(USER, "Coins"), 500)
		T.equal(H.stored(world, USER).saveSeq, before.saveSeq, "nothing written")
	end)

	test("a server that lost the lock never writes its hatch", function()
		local world = H.world()
		local first = H.server(world, "A")
		local g = gameOn(first)
		first.core.load(USER)
		g.currency.add(USER, "Coins", 500, "Sell")
		first.core.autosaveAll()
		world.clock.advance(H.Config.LockTimeout + 1)
		local second = H.server(world, "B")
		second.core.load(USER)

		T.isTrue((g.eggs.purchase(USER, 1, "Remote")))
		first.core.autosaveAll()
		T.equal(first.core.getStatus(USER), "Lost")
		local coins, pets = stored(world)
		T.equal(coins, 500)
		T.equal(count(pets), 0)
	end)
end)

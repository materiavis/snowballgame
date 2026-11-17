--!strict
-- Finds against DataService and the fake store (#40 AC5, AC12): the concept 6.5 rows that apply
-- to a find. FindCore reads profiles through DataCore.getData, exactly as the Roblox layer does
-- through DataService.GetProfile, and puts the value into the real SellCore (the ball).
-- 6.5 "Spieler verlässt das Spiel, während er einen Ball schiebt: Ballgrösse und Funde im Ball
-- verfallen ... Funde stehen schon ab dem Aufsammeln im Sammelbuch."

local T = require("../../../TestKit")
local H = require("../../../server/DataService/Harness")
local FindWorld = require("./FindWorld")
local SellConfig = require("../../../../src/shared/Config/Sell")
local SellCore = require("../../../../src/places/simulator/server/SellService/SellCore")
local SaleOverride = require("../../../../src/places/simulator/server/SellService/SaleOverride")

local E = FindWorld.E
local USER = H.USER
local FLAGS = SaleOverride.flagNames(E.Config.Economy)

type Game = { finds: FindWorld.World, sell: SellCore.Core }

-- FindCore + SellCore on one simulated server, with one zone 1 point.
local function gameOn(server: H.Server): Game
	local function getProfile(userId: number): any
		return server.core.getData(userId)
	end
	local sell = SellCore.new({
		economy = E.Economy,
		ballValue = E.Zones.ballValue,
		config = SellConfig,
		getProfile = getProfile,
		sizeMetres = function(): number?
			return 0.2
		end,
		resetBall = function(): boolean
			return true
		end,
		petMultiplier = function(): any
			return nil
		end,
		sellValueLevel = function(): number
			return 0
		end,
		sellMultiplier = function(): number
			return 1
		end,
		bonusFlags = function(): any
			return SaleOverride.noFlags(FLAGS)
		end,
		addCoins = function(): (boolean, any)
			return true, 0
		end,
		log = function() end,
	})
	local finds = FindWorld.new({
		getProfile = getProfile,
		addFindValue = function(userId: number, value: number): (boolean, string?)
			return sell.addFindValue(userId, value)
		end,
	})
	finds.core.addPoint("P", 1, 0, 0, 0, "P")
	return { finds = finds, sell = sell }
end

-- Activate (as on Loaded), force the rarity and pick the point's find up.
local function pick(g: Game, rarity: string): boolean
	local core = g.finds.core
	if not core.isActive(USER) then
		core.activate(USER)
	end
	core.setForce(USER, { rarity = rarity })
	core.spawnNow(USER)
	local point = core.points()[1]
	return core.pickup(USER, FindWorld.ballOn(point, 1), 4, true) == 1
end

local function storedFinds(world: H.World): any
	local record = H.stored(world, USER)
	return record and record.data.sim.collection.finds
end

return T.suite("FindService save rules (6.5)", function(test)
	test("AC5: a find is in the profile from the pickup on and lands with the next autosave", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		server.core.autosaveAll()
		T.equal(pick(g, "Rare"), true)
		T.isTrue(server.core.getData(USER).sim.collection.finds.Edelweiss ~= nil, "in the live profile at once")
		T.equal(storedFinds(world).Edelweiss, nil, "a find is not an immediate save (6.5 list, ADR 0003)")
		server.core.autosaveAll()
		T.equal(storedFinds(world).Edelweiss, FindWorld.UNIX, "stored with its first time")
	end)

	test("AC5 + 6.5: picked up, then the player leaves: the find is stored, the ball and its finds lapse", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		T.equal(pick(g, "Epic"), true)
		T.isTrue(g.sell.findsValue(USER) > 0, "the value is in the ball")
		-- Leaving: DataService saves and releases, SellService and FindService forget the ball.
		T.equal(server.core.release(USER, "Leave"), true)
		g.sell.forget(USER)
		g.finds.core.forget(USER)
		T.equal(storedFinds(world).RockCrystal, FindWorld.UNIX, "the leave save stored the find")

		local restarted = H.server(world, "B")
		local again = gameOn(restarted)
		restarted.core.load(USER)
		local profile = restarted.core.getData(USER)
		T.equal(profile.sim.collection.finds.RockCrystal, FindWorld.UNIX, "in the collection after rejoining")
		T.equal(again.sell.findsValue(USER), 0, "the finds in the ball lapsed")
		T.equal(#again.finds.core.ballFinds(USER), 0)
		-- The save format has no field for the ball or its finds (6.5, ADR 0003).
		for key in profile.sim do
			T.isTrue(string.find(string.lower(key), "ball") == nil or key == "ballSkins", `no ball state in sim.{key}`)
		end
	end)

	test("AC12 6.5 Speichern: a forced save failure keeps the find on the server; the next save stores it", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		T.equal(pick(g, "Common"), true)
		server.core.autosaveAll()
		T.equal(storedFinds(world).PineCone, FindWorld.UNIX)

		T.equal(pick(g, "Uncommon"), true)
		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.save(USER, "Autosave"), false, "forced save failure")
		local stored = storedFinds(world)
		T.equal(stored.ChocolateBar, nil, "the store keeps the older state")
		T.equal(stored.PineCone, FindWorld.UNIX, "nothing older or empty was written over it")
		T.equal(server.core.getStatus(USER), "Loaded", "a failed save does not end the session")
		T.isTrue(server.core.getData(USER).sim.collection.finds.ChocolateBar ~= nil, "kept on the server")

		T.equal(pick(g, "Rare"), true, "finds go on while saves fail")
		world.store:setFailing("UpdateAsync", false)
		T.equal(server.core.save(USER, "Retry"), true)
		stored = storedFinds(world)
		T.equal(stored.ChocolateBar, FindWorld.UNIX, "the next save stores both")
		T.equal(stored.Edelweiss, FindWorld.UNIX)
	end)

	test("AC12: a save failure on leave keeps the lock, and a later autosave stores the find", function()
		local world = H.world()
		local server = H.server(world, "A")
		local g = gameOn(server)
		server.core.load(USER)
		T.equal(pick(g, "Secret"), true)
		world.store:setFailing("UpdateAsync", true)
		T.equal(server.core.release(USER, "Leave"), false)
		world.store:setFailing("UpdateAsync", false)
		server.core.autosaveAll()
		T.equal(storedFinds(world).YetiFootprint, FindWorld.UNIX)
		T.equal(H.stored(world, USER).data.sim.titles.YetiTracker, true, "with its title")
	end)

	test("6.5 Laden: while the profile is not loaded no find spawns or is picked up, nothing is written", function()
		local world = H.world()
		world.store:setFailing("UpdateAsync", true)
		local server = H.server(world, "A")
		local g = gameOn(server)
		local spawned: number? = nil
		server.onWait = function()
			if server.core.getStatus(USER) == "Failed" and spawned == nil then
				g.finds.core.activate(USER)
				g.finds.clock.advance(60)
				spawned = g.finds.core.step(USER) + g.finds.core.spawnNow(USER)
				world.store:setFailing("UpdateAsync", false)
			end
		end
		T.equal(server.core.load(USER), "Loaded")
		T.equal(spawned, 0, "nothing spawned while not loaded")
		T.equal(next(storedFinds(world)), nil)
		T.equal(pick(g, "Common"), true, "once loaded it works")
	end)

	test("6.5 Serverabsturz: at most the last autosave interval of finds is lost; a lost lock never writes", function()
		local world = H.world()
		local first = H.server(world, "A")
		local g = gameOn(first)
		first.core.load(USER)
		T.equal(pick(g, "Common"), true)
		first.core.autosaveAll()
		T.equal(pick(g, "Rare"), true) -- after the last autosave: lost in the crash
		-- Server A dies without saving; B takes the lock once it is stale.
		world.clock.advance(H.Config.LockTimeout + 1)
		local second = H.server(world, "B")
		second.core.load(USER)
		local profile = second.core.getData(USER)
		T.equal(profile.sim.collection.finds.PineCone, FindWorld.UNIX, "saved before the crash")
		T.equal(profile.sim.collection.finds.Edelweiss, nil, "the last interval is lost (6.5: at most 2 min)")
		T.equal(H.Config.AutosaveInterval, 120)
		-- A's late save is refused: the find of the lost session never reaches the store.
		first.core.autosaveAll()
		T.equal(first.core.getStatus(USER), "Lost")
		T.equal(storedFinds(world).Edelweiss, nil)
	end)
end)

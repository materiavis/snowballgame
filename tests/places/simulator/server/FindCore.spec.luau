--!strict
-- FindCore (#40, concept 7.7, 8.5, ADR 0016) on the real Config.Finds, Rng odds and
-- Formulas.Economy.findValue: spawns only at points and every 20 s (AC1), values as a share of a
-- full ball of the zone typed in from the concept (AC2), no Legendary in zones 1-5 (AC3), finds
-- in the ball until the sale (AC4), the collection at pickup (AC5), the Magnet radius (AC6) and
-- the server-side pickup checks (AC9).

local T = require("../../../TestKit")
local FindWorld = require("./FindWorld")
local SellConfig = require("../../../../src/shared/Config/Sell")
local SellCore = require("../../../../src/places/simulator/server/SellService/SellCore")
local SaleOverride = require("../../../../src/places/simulator/server/SellService/SaleOverride")
local FindCore = require("../../../../src/places/simulator/server/FindService/FindCore")

local E = FindWorld.E
local USER, OTHER = FindWorld.USER, FindWorld.OTHER
local Config = FindWorld.Config
local RADIUS = 1 -- studs, a small ball

-- Concept 8.3 typed in by hand: a full ball of zone n is 10 x (2 x 1.25^(n-1))^3.
local function fullBall(zone: number): number
	return 10 * (2 * 1.25 ^ (zone - 1)) ^ 3
end

local function points(w: FindWorld.World): { FindCore.Point }
	return w.core.points()
end

local function spawnedAt(w: FindWorld.World, userId: number, slot: number): FindCore.Spawned?
	for _, spawned in w.core.spawned(userId) do
		if spawned.slot == slot then
			return spawned
		end
	end
	return nil
end

-- One point per zone along x, all activated for USER and spawned.
local function zoneRow(w: FindWorld.World, zones: { number }): { [number]: FindCore.Point }
	local byZone = {}
	for index, zone in zones do
		w.core.addPoint(`P{zone}`, zone, index * 100, 0, 0, `Point{zone}`)
		w.unlocked[zone] = true
	end
	for _, point in points(w) do
		byZone[point.zone] = point
	end
	return byZone
end

return T.suite("FindService.FindCore (7.7)", function(test)
	test("AC1: finds appear only at the bound points, once a point has been empty for 20 s", function()
		local w = FindWorld.new()
		T.equal(Config.SpawnInterval, 20, "concept 7.7: alle 20 Sekunden")
		local a = w.core.addPoint("A", 1, 10, 0, 5, "A")
		local b = w.core.addPoint("B", 1, 30, 2, -5, "B")
		w.core.activate(USER)
		T.equal(w.core.step(USER), 0, "nothing at once")
		w.clock.advance(19.9)
		T.equal(w.core.step(USER), 0, "nothing before 20 s")
		w.clock.advance(0.1)
		T.equal(w.core.step(USER), 2, "one find per point at 20 s")
		T.equal(w.core.step(USER), 0, "a point holds at most one find")
		w.clock.advance(100)
		T.equal(w.core.step(USER), 0, "still one: no new find while the old one lies there")
		local spawns = FindWorld.of(w, "Spawn", USER)
		T.equal(#spawns, 2)
		for _, event in spawns do
			local point = event.point :: FindCore.Point
			T.isTrue(event.slot == a or event.slot == b, "at a bound slot")
			T.equal(point.slot, event.slot, "with that point's position")
			T.isTrue((point.x == 10 and point.z == 5) or (point.x == 30 and point.y == 2), "the anchor position")
		end
	end)

	test("AC1: after a pickup the same point gets its next find exactly 20 s later", function()
		local w = FindWorld.new()
		w.core.addPoint("A", 1, 0, 0, 0, "A")
		w.core.activate(USER)
		w.clock.advance(20)
		w.core.step(USER)
		local point = points(w)[1]
		T.equal(w.core.pickup(USER, FindWorld.ballOn(point, RADIUS), 4, true), 1, "picked up")
		local pickedAt = w.clock.now()
		w.clock.advance(19.75)
		T.equal(w.core.step(USER), 0, "not before 20 s")
		w.clock.advance(0.25)
		T.equal(w.core.step(USER), 1, "new find at 20 s")
		local spawned = spawnedAt(w, USER, point.slot) :: FindCore.Spawned
		T.equal(spawned.at - pickedAt, 20)
	end)

	test("7.7 🟦: every player has their own finds; nobody takes another's", function()
		local w = FindWorld.new()
		w.core.addPoint("A", 1, 0, 0, 0, "A")
		w.core.activate(USER)
		w.core.activate(OTHER)
		w.clock.advance(20)
		T.equal(w.core.step(USER), 1)
		T.equal(w.core.step(OTHER), 1)
		local point = points(w)[1]
		T.equal(w.core.pickup(USER, FindWorld.ballOn(point, RADIUS), 4, true), 1)
		T.isTrue(spawnedAt(w, OTHER, point.slot) ~= nil, "the other player's find is still there")
		T.equal(#FindWorld.of(w, "Collect", OTHER), 0)
		T.equal(#w.core.ballFinds(OTHER), 0)
		T.equal(w.core.pickup(OTHER, FindWorld.ballOn(point, RADIUS), 4, true), 1, "and theirs to pick up")
	end)

	test("AC1: a removed point takes its finds with it; a new point starts its 20 s", function()
		local w = FindWorld.new()
		w.core.addPoint("A", 1, 0, 0, 0, "A")
		w.core.activate(USER)
		w.clock.advance(20)
		w.core.step(USER)
		T.equal(w.core.removePoint("A"), true)
		T.equal(#w.core.spawned(USER), 0)
		T.equal(#FindWorld.of(w, "Remove", USER), 1)
		T.equal(w.core.removePoint("A"), false, "only once")
		local slot = w.core.addPoint("B", 1, 5, 0, 0, "B")
		T.equal(w.core.addPoint("B", 1, 5, 0, 0, "B"), slot, "binding twice keeps one slot")
		w.clock.advance(19)
		T.equal(w.core.step(USER), 0)
		w.clock.advance(1)
		T.equal(w.core.step(USER), 1)
	end)

	test("AC2: the value is the fixed share of a full ball of the find's zone (2/5/15/50/200 %)", function()
		local shares = { Common = 0.02, Uncommon = 0.05, Rare = 0.15, Epic = 0.5, Legendary = 2 }
		for rarity, share in shares do
			T.equal(Config.Values[rarity], share, `7.7 table: {rarity}`)
		end
		local w = FindWorld.new()
		local byZone = zoneRow(w, { 1, 2, 3, 4, 5, 6, 10 })
		w.core.activate(USER)
		for rarity, share in shares do
			w.core.setForce(USER, { rarity = rarity })
			w.added = {}
			w.core.spawnNow(USER)
			for zone, point in byZone do
				local expected = if rarity == "Legendary" and zone < 6 then nil else share * fullBall(zone)
				local before = #w.added
				w.core.pickup(USER, FindWorld.ballOn(point, RADIUS), 4, true)
				if expected then
					T.equal(#w.added, before + 1, `{rarity} zone {zone} picked`)
					T.near(w.added[#w.added].value, expected, expected * 1e-12, `{rarity} in zone {zone}`)
				end
			end
		end
		T.near(fullBall(1) * 0.02, 1.6, 1e-12, "a Pine Cone in zone 1 is worth 1.6")
		T.near(fullBall(5) * 0.5, 0.5 * 80 * 1.953125 ^ 4, 1e-9, "a Rock Crystal in zone 5: 50 % of 80 x 1.953^4")
	end)

	test("AC2 + AC4: the value goes into the ball's sale and the finds stick in it until the sale", function()
		local sell: SellCore.Core
		local w = FindWorld.new({
			addFindValue = function(userId: number, value: number): (boolean, string?)
				return sell.addFindValue(userId, value)
			end,
		})
		local flags = SaleOverride.flagNames(E.Config.Economy)
		sell = SellCore.new({
			economy = E.Economy,
			ballValue = E.Zones.ballValue,
			config = SellConfig,
			getProfile = function(userId: number): any
				return w.profiles[userId]
			end,
			sizeMetres = function(): number?
				return 2
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
				return SaleOverride.noFlags(flags)
			end,
			addCoins = function(): (boolean, any)
				return true, 0
			end,
			log = function() end,
		})
		sell.subscribe(function(event: any)
			if event.kind == "Sale" then
				w.core.clearBall(event.userId)
			end
		end)
		local byZone = zoneRow(w, { 1, 3 })
		w.core.activate(USER)
		w.core.setForce(USER, { rarity = "Epic" })
		w.core.spawnNow(USER)
		w.core.pickup(USER, FindWorld.ballOn(byZone[1], RADIUS), 4, true)
		w.core.pickup(USER, FindWorld.ballOn(byZone[3], RADIUS), 4, true)
		local expected = 0.5 * fullBall(1) + 0.5 * fullBall(3)
		T.near(sell.findsValue(USER), expected, 1e-9, "both finds in the ball's value")
		T.equal(table.concat(w.core.ballFinds(USER), ","), "RockCrystal,RockCrystal", "stuck in the ball")

		-- More steps, a respawn round and a deactivate do not take them out of the ball.
		w.clock.advance(60)
		w.core.step(USER)
		w.core.deactivate(USER)
		w.core.activate(USER)
		T.equal(#w.core.ballFinds(USER), 2, "still in the ball")

		local ok, sale = sell.sell(USER, 1)
		T.equal(ok, true)
		T.equal(sale.findsValue, expected, "the sale paid the finds")
		T.equal(sale.coins, math.floor(80 + expected), "(10 x 2^3 + finds) x 1")
		T.equal(#w.core.ballFinds(USER), 0, "the sale empties the ball")
		T.equal(sell.findsValue(USER), 0)
		T.equal(#FindWorld.of(w, "ClearBall", USER), 1)
		w.core.forget(USER)
		T.equal(#w.core.ballFinds(USER), 0, "leaving forgets the ball")
	end)

	test("AC3: zones 1-5 never get a Legendary, also not with a forced roll or rarity; 6-10 do", function()
		local w = FindWorld.new()
		local zones = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
		local byZone = zoneRow(w, zones)
		w.core.activate(USER)
		-- 0.995 lies in the Legendary band of zones 6-10 (98.95..99.95 %) and in Epic below zone 6.
		w.core.setForce(USER, { roll = 0.995 })
		w.core.spawnNow(USER)
		for zone, point in byZone do
			local spawned = spawnedAt(w, USER, point.slot) :: FindCore.Spawned
			T.equal(spawned.rarity, if zone >= 6 then "Legendary" else "Epic", `zone {zone}`)
			T.equal(spawned.findId, if zone >= 6 then "GoldenCowbell" else "RockCrystal")
		end
		w.core.setForce(USER, { rarity = "Legendary" })
		w.events = {}
		w.core.spawnNow(USER)
		for _, event in FindWorld.of(w, "Spawn", USER) do
			if (event.zone :: number) < 6 then
				T.isTrue(event.rarity ~= "Legendary", `forced Legendary refused in zone {event.zone}`)
				T.equal(event.forceRefused, "Legendary")
			else
				T.equal(event.rarity, "Legendary")
				T.equal(event.forced, "Rarity")
			end
		end
		w.core.setForce(USER, nil)
		local seen: { [string]: boolean } = {}
		for _ = 1, 2000 do
			w.events = {}
			w.core.spawnNow(USER)
			for _, event in FindWorld.of(w, "Spawn", USER) do
				if (event.zone :: number) < 6 then
					T.isTrue(event.rarity ~= "Legendary", "no Legendary in zones 1-5")
				elseif event.rarity == "Legendary" then
					seen[tostring(event.zone)] = true
				end
			end
		end
		T.isTrue(next(seen) ~= nil, "Legendary finds do appear in zones 6-10")
	end)

	test("AC5: a pickup writes sim.collection.finds[id] at once, with the first time only", function()
		local w = FindWorld.new()
		local byZone = zoneRow(w, { 1 })
		w.core.activate(USER)
		w.core.setForce(USER, { rarity = "Common" })
		w.core.spawnNow(USER)
		w.core.pickup(USER, FindWorld.ballOn(byZone[1], RADIUS), 4, true)
		local finds = w.profiles[USER].sim.collection.finds
		T.equal(finds.PineCone, FindWorld.UNIX, "in the profile from the pickup on")
		T.equal(FindWorld.of(w, "Collect", USER)[1].first, true)
		w.core.spawnNow(USER)
		w.core.pickup(USER, FindWorld.ballOn(byZone[1], RADIUS), 4, true)
		T.equal(finds.PineCone, FindWorld.UNIX, "the first time stays")
		T.equal(FindWorld.of(w, "Collect", USER)[2].first, false)
		T.equal(#w.core.ballFinds(USER), 2, "both count in the ball")
		-- A malformed collection is left alone, never repaired; the find still counts.
		w.profiles[USER].sim.collection = "broken"
		w.core.spawnNow(USER)
		w.core.pickup(USER, FindWorld.ballOn(byZone[1], RADIUS), 4, true)
		T.equal(w.profiles[USER].sim.collection, "broken")
		T.equal(#w.core.ballFinds(USER), 3)
		T.isTrue(FindWorld.of(w, "Collect", USER)[3].collectionProblem ~= nil)
	end)

	test("AC6: the pickup reach is the Magnet effect (4 studs, 24 at level 100) from the ball's surface", function()
		T.equal(E.Upgrades.effect("magnet", 0), 4)
		T.equal(E.Upgrades.effect("magnet", 100), 24)
		local w = FindWorld.new()
		local byZone = zoneRow(w, { 1 })
		w.core.activate(USER)
		w.core.spawnNow(USER)
		local point = byZone[1]
		-- A ball of radius 3 whose centre is 15 studs from the point: its surface is 12 away.
		local ball = { x = point.x + 15, y = point.y, z = point.z, radius = 3 }
		T.equal(FindCore.gap(ball, point), 12)
		T.equal(w.core.pickup(USER, ball, E.Upgrades.effect("magnet", 0), true), 0, "out of reach at level 0")
		T.equal(w.core.pickup(USER, ball, E.Upgrades.effect("magnet", 40), true), 1, "12 studs at level 40")
		w.core.spawnNow(USER)
		local edge = { x = point.x + 7, y = point.y, z = point.z, radius = 3 }
		T.equal(w.core.pickup(USER, edge, 4, true), 1, "exactly 4 studs from the surface is in reach")
		w.core.spawnNow(USER)
		T.equal(w.core.pickup(USER, { x = point.x + 7.01, y = point.y, z = point.z, radius = 3 }, 4, true), 0)
		T.equal(w.core.pickup(USER, ball, 24, true), 1, "the next check uses the new radius at once")
	end)

	test("secret find: Yeti Footprint, no coins, the title once and its ball effect", function()
		local w = FindWorld.new()
		local byZone = zoneRow(w, { 2 })
		w.core.activate(USER)
		w.core.setForce(USER, { rarity = "Secret" })
		w.core.spawnNow(USER)
		T.equal(w.core.spawned(USER)[1].findId, "YetiFootprint")
		T.equal(FindCore.ballEffectOf(Config, w.profiles[USER]), nil, "no effect before")
		w.core.pickup(USER, FindWorld.ballOn(byZone[2], RADIUS), 4, true)
		local event = FindWorld.of(w, "Collect", USER)[1]
		T.equal(event.value, 0, "no coin value")
		T.equal(w.added[1].value, 0)
		T.equal(event.title, "YetiTracker")
		T.equal(event.newTitle, true)
		T.equal(w.profiles[USER].sim.titles.YetiTracker, true, "title in sim.titles")
		T.equal(w.profiles[USER].sim.collection.finds.YetiFootprint, FindWorld.UNIX)
		T.equal(FindCore.ballEffectOf(Config, w.profiles[USER]), "YetiSparkles")
		w.core.spawnNow(USER)
		w.core.pickup(USER, FindWorld.ballOn(byZone[2], RADIUS), 4, true)
		T.equal(FindWorld.of(w, "Collect", USER)[2].newTitle, false, "the title only once")
		T.equal(#w.core.ballFinds(USER), 2, "it sticks in the ball like any find")
	end)

	test("AC9: the server picks up only with the owner at the ball and the find's zone unlocked", function()
		local w = FindWorld.new()
		local byZone = zoneRow(w, { 1, 6 })
		w.unlocked[6] = nil
		w.core.activate(USER)
		w.core.spawnNow(USER)
		local onOne = FindWorld.ballOn(byZone[1], RADIUS)
		T.equal(w.core.pickup(USER, onOne, 4, false), 0, "owner not at the ball")
		T.equal(w.core.pickup(USER, onOne, 4, false), 0)
		local refusals = FindWorld.of(w, "Refused", USER)
		T.equal(#refusals, 1, "a refusal is reported once, not every check")
		T.equal(refusals[1].refusal, FindCore.Refusal.NotHeld)
		T.equal(w.core.pickup(USER, FindWorld.ballOn(byZone[6], RADIUS), 4, true), 0, "zone 6 is locked")
		T.equal(FindWorld.of(w, "Refused", USER)[2].refusal, FindCore.Refusal.Locked)
		T.equal(#w.added, 0, "no value added")
		T.equal(next(w.profiles[USER].sim.collection.finds), nil, "nothing recorded")
		local nan = 0 / 0
		T.equal(w.core.pickup(USER, { x = nan, y = 0, z = 0, radius = 1 }, 4, true), 0, "a broken ball")
		T.equal(w.core.pickup(USER, nil, 4, true), 0, "no ball")
		local near = { x = byZone[1].x + RADIUS + 2, y = byZone[1].y, z = byZone[1].z, radius = RADIUS }
		T.equal(w.core.pickup(USER, near, nan, true), 0, "a broken radius reaches nothing beyond the ball")
		T.equal(w.core.pickup(USER, onOne, 4, true), 1, "then it works")
	end)

	test("6.5 Laden: no spawn and no pickup while the profile is not loaded or not activated", function()
		local w = FindWorld.new()
		local byZone = zoneRow(w, { 1 })
		w.clock.advance(100)
		T.equal(w.core.step(USER), 0, "not activated")
		w.core.activate(USER)
		w.loaded[USER] = false
		w.clock.advance(100)
		T.equal(w.core.step(USER), 0, "not loaded")
		T.equal(w.core.spawnNow(USER), 0)
		w.loaded[USER] = true
		w.core.spawnNow(USER)
		w.loaded[USER] = false
		T.equal(w.core.pickup(USER, FindWorld.ballOn(byZone[1], RADIUS), 4, true), 0, "no pickup either")
		w.loaded[USER] = true
		w.core.deactivate(USER)
		T.equal(#w.core.spawned(USER), 0, "deactivate drops the spawned finds")
		T.equal(FindWorld.of(w, "Reset", USER)[2].reason, "Deactivate")
		T.equal(w.core.pickup(USER, FindWorld.ballOn(byZone[1], RADIUS), 4, true), 0)
	end)

	test("a world without a find of the rolled rarity spawns nothing and warns once", function()
		local w = FindWorld.new()
		w.core.addPoint("W2", 11, 0, 0, 0, "World2") -- zone 11 is world 2: no catalogue yet
		w.core.activate(USER)
		w.core.setForce(USER, { rarity = "Common" })
		T.equal(w.core.spawnNow(USER), 0)
		T.equal(w.core.spawnNow(USER), 0)
		T.equal(#w.logs, 1, "one warning")
		T.equal(FindWorld.of(w, "Refused", USER)[1].refusal, FindCore.Refusal.NoFind)
		T.equal(w.core.findFor(11, "Secret"), "YetiFootprint", "the secret find exists in every world")
	end)
end)

--!strict
-- The group chest (issue #37 AC6, AC9, AC12; ADR 0015) against DataCore, CurrencyCore and the
-- fake store: once per player, members only, a double tap is one open, the reach and rate are
-- the server's, and the claim and the reward stay together across a forced save failure, a
-- rejoin and a crash.

local T = require("../../../TestKit")
local H = require("../../../server/DataService/Harness")
local FakeClock = require("../../../helpers/FakeClock")
local CurrencyConfig = require("../../../../src/shared/Config/Currency")
local CurrencyCore = require("../../../../src/server/Services/CurrencyService/CurrencyCore")
local EconomyConfig = require("../../../../src/shared/Config/Economy")
local LobbyConfig = require("../../../../src/shared/Config/Lobby")
local ChestCore = require("../../../../src/places/lobby/server/GroupChestService/ChestCore")

local USER = H.USER
local REACH = 14

local function setUp(world: any?, jobId: string?)
	local w = world or H.world()
	local server = H.server(w, jobId or "A")
	server.core.load(USER)
	local clock = FakeClock.new(0)
	local currency = CurrencyCore.new({
		config = CurrencyConfig :: any,
		getProfile = function(userId: number)
			return server.core.getData(userId)
		end,
		log = function() end,
	})
	local h: any = {
		world = w,
		server = server,
		clock = clock,
		currency = currency,
		member = "Member",
		saves = 0,
		onMembership = nil,
	}
	h.chest = ChestCore.new({
		coins = EconomyConfig.GroupChestCoins,
		snowCoins = EconomyConfig.GroupChestSnowCoins,
		cooldown = LobbyConfig.GroupChestCooldown,
		reach = REACH,
		now = clock.now,
		getProfile = function(userId: number)
			return server.core.getData(userId)
		end,
		membership = function(userId: number)
			if h.onMembership then
				h.onMembership(userId)
			end
			return h.member
		end,
		addCoins = function(userId: number, amount: number): boolean
			return (currency.add(userId, "Coins", amount, "GroupChest"))
		end,
		addSnowCoins = function(userId: number, amount: number): boolean
			return (currency.add(userId, "SnowCoins", amount, "GroupChest"))
		end,
		granted = function()
			h.shownAtSave = h.saves
		end,
		save = function(userId: number): boolean
			h.saves += 1
			return (server.core.save(userId, "GroupChest"))
		end,
		log = function() end,
	})
	-- A new attempt after the cooldown.
	function h.open(distance: number?): any
		h.clock.advance(LobbyConfig.GroupChestCooldown)
		return h.chest.open(USER, distance or 3)
	end
	return h
end

local function balances(h: any): (number?, number?)
	return h.currency.get(USER, "Coins"), h.currency.get(USER, "SnowCoins")
end

local function stored(world: any): any
	return H.stored(world, USER).data
end

return T.suite("Lobby group chest (7.1, 6.5)", function(test)
	test("AC10: the reward and the placeholder group id come from Config.Economy", function()
		T.equal(EconomyConfig.GroupChestCoins, 500)
		T.equal(EconomyConfig.GroupChestSnowCoins, 100)
		T.equal(EconomyConfig.GroupId, 0, "placeholder until humans fill it in")
	end)

	test("AC6: a member gets 500 Coins and 100 Snow Coins once, saved at once", function()
		local h = setUp()
		local result = h.open()
		T.equal(result.outcome, "Opened")
		T.equal(result.saved, true)
		T.equal(h.shownAtSave, 0, "the reward is shown before the save, not after its retries")
		local coins, snow = balances(h)
		T.equal(coins, 500)
		T.equal(snow, 100)
		T.equal(stored(h.world).groupChestClaimed, true, "stored by the immediate save")
		T.equal(stored(h.world).sim.coins, 500)
		T.equal(stored(h.world).fight.snowCoins, 100)
		T.equal(h.open().outcome, "AlreadyOpened")
		T.equal(h.open().outcome, "AlreadyOpened")
		coins, snow = balances(h)
		T.equal(coins, 500, "never twice")
		T.equal(snow, 100)
	end)

	test("AC6: non-members get nothing and can open after joining", function()
		local h = setUp()
		h.member = "NotMember"
		T.equal(h.open().outcome, "NotMember")
		T.equal((balances(h)), 0)
		T.equal(h.server.core.getData(USER).groupChestClaimed, false)
		h.member = "NoGroup"
		T.equal(h.open().outcome, "NoGroup", "group id 0: nobody is a member")
		h.member = "Error"
		T.equal(h.open().outcome, "TryLater", "a failed web call opens nothing")
		T.equal(h.saves, 0, "nothing to save")
		h.member = "Member"
		T.equal(h.open().outcome, "Opened")
	end)

	test("AC6/AC9: a double tap is one open (Busy while the membership check runs, then Cooldown)", function()
		local h = setUp()
		local inner: any = nil
		h.onMembership = function()
			inner = h.chest.open(USER, 3)
		end
		h.clock.advance(LobbyConfig.GroupChestCooldown)
		T.equal(h.chest.open(USER, 3).outcome, "Opened")
		T.equal(inner.outcome, "Busy")
		T.equal(h.chest.open(USER, 3).outcome, "Cooldown", "again within the cooldown")
		T.equal((balances(h)), 500)
	end)

	test("AC9: the server's distance decides; anything beyond reach or not a number opens nothing", function()
		local h = setUp()
		T.equal(h.open(REACH + 0.01).outcome, "TooFar")
		T.equal(h.open(0 / 0).outcome, "TooFar")
		T.equal(h.open(math.huge).outcome, "TooFar")
		T.equal(h.open(REACH).outcome, "Opened")
	end)

	test("6.5 Laden: no profile, no chest", function()
		local h = setUp()
		T.equal(h.server.core.release(USER, "Leave"), true, "the session ends: no profile here")
		T.equal(h.open().outcome, "NotReady")
		T.equal(h.saves, 0)
	end)

	test("AC12 forced save failure: the claim and the reward stay together and land with the next save", function()
		local h = setUp()
		h.world.store:setFailing("UpdateAsync", true)
		local result = h.open()
		T.equal(result.outcome, "Opened")
		T.equal(result.saved, false, "the immediate save failed")
		T.equal(stored(h.world).groupChestClaimed, false, "the store still has the old record")
		T.equal(stored(h.world).sim.coins, 0)
		T.equal(h.open().outcome, "AlreadyOpened", "no second open while the save is pending")
		h.world.store:setFailing("UpdateAsync", false)
		T.equal(h.server.core.autosaveAll(), 1)
		T.equal(stored(h.world).groupChestClaimed, true)
		T.equal(stored(h.world).sim.coins, 500)
		T.equal(stored(h.world).fight.snowCoins, 100)
	end)

	test("AC12 failed save, then a rejoin: exactly once", function()
		local h = setUp()
		h.world.store:setFailing("UpdateAsync", true)
		T.equal(h.open().outcome, "Opened")
		-- Leave while the store still fails: the release keeps the lock and the state here, and a
		-- rejoin onto this server resumes it (DataSimulateRejoin path).
		T.equal((h.server.core.release(USER, "Leave")), false)
		T.equal(h.server.core.load(USER), "Loaded")
		T.equal(h.open().outcome, "AlreadyOpened")
		T.equal((balances(h)), 500)
		-- The store recovers; leave and join another server.
		h.world.store:setFailing("UpdateAsync", false)
		T.equal(h.server.core.release(USER, "Leave"), true)
		local other = setUp(h.world, "B")
		T.equal(other.server.core.getData(USER).groupChestClaimed, true)
		T.equal(other.open().outcome, "AlreadyOpened")
		local coins, snow = balances(other)
		T.equal(coins, 500)
		T.equal(snow, 100)
	end)

	test("AC12 crash before any save: claim and reward are lost together, so the player opens once", function()
		local world = H.world()
		local h = setUp(world, "A")
		h.world.store:setFailing("UpdateAsync", true)
		T.equal(h.open().outcome, "Opened")
		-- Server A dies without a save; its lock goes stale.
		h.world.store:setFailing("UpdateAsync", false)
		world.clock.advance(H.Config.LockTimeout + 1)
		local other = setUp(world, "B")
		local profile = other.server.core.getData(USER)
		T.equal(profile.groupChestClaimed, false)
		T.equal(profile.sim.coins, 0, "no coins without the flag")
		T.equal(other.open().outcome, "Opened")
		T.equal((balances(other)), 500)
	end)
end)

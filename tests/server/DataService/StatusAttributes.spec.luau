--!strict
-- DataLoadStatus is written on every server, the diagnostics only in Studio (ADR 0006, ADR 0008).
-- The listener runs against a real DataCore and fake store, as on a live server (diagnostics off)
-- and in Studio (on). The Roblox wiring in init.luau cannot load under Lune, so it is checked
-- as text: the listener is subscribed outside the Studio branch.

local T = require("../../TestKit")
local H = require("./Harness")
local FakePlayer = require("../../helpers/FakePlayer")
local SourceSection = require("../../helpers/SourceSection")
local StatusAttributes = require("../../../src/server/Services/DataService/StatusAttributes")

local USER = H.USER
local SERVICE_FILE = "src/server/Services/DataService/init.luau"

local function attach(server: H.Server, player: FakePlayer.FakePlayer, diagnostics: boolean)
	server.core.subscribe(StatusAttributes.listener({
		getPlayer = function(userId: number): any
			return if userId == player.UserId then player else nil
		end,
		getSaveSeq = server.core.getSaveSeq,
		diagnostics = diagnostics,
	}))
end

local function seedProfile(world: H.World)
	local server = H.server(world, "Seed")
	server.core.load(USER)
	server.core.getData(USER).sim.coins = 500
	server.core.release(USER, "Leave")
end

return T.suite("DataService status attributes", function(test)
	test("live server: a join ends with DataLoadStatus Loaded and no diagnostic attribute", function()
		local world = H.world()
		local server = H.server(world, "Live")
		local player = FakePlayer.new(USER)
		attach(server, player, false)
		T.equal(server.core.load(USER), "Loaded")
		T.equal(player:GetAttribute("DataLoadStatus"), "Loaded")
		T.equal(table.concat(player.names(), ","), "DataLoadStatus", "only the live attribute is set")
	end)

	test("live server: Failed is written while loading fails, then Loaded after the retry", function()
		local world = H.world()
		seedProfile(world)
		world.store:setFailing("UpdateAsync", true)
		local server = H.server(world, "Live")
		local player = FakePlayer.new(USER)
		attach(server, player, false)
		local sawFailed = false
		server.onWait = function()
			if server.core.getStatus(USER) == "Failed" and not sawFailed then
				sawFailed = true
				T.equal(player:GetAttribute("DataLoadStatus"), "Failed", "the HUD can show the hint")
				world.store:setFailing("UpdateAsync", false)
			end
		end
		T.equal(server.core.load(USER), "Loaded")
		T.isTrue(sawFailed, "status was Failed before the retry")
		T.equal(player:GetAttribute("DataLoadStatus"), "Loaded")
		T.equal(table.concat(player.names(), ","), "DataLoadStatus")
	end)

	test("live server: saves and release write no diagnostic attribute", function()
		local world = H.world()
		local server = H.server(world, "Live")
		local player = FakePlayer.new(USER)
		attach(server, player, false)
		server.core.load(USER)
		server.core.autosaveAll()
		world.store:setFailing("UpdateAsync", true)
		server.core.save(USER, "Barrier")
		world.store:setFailing("UpdateAsync", false)
		server.core.release(USER, "Leave")
		T.equal(player:GetAttribute("DataLoadStatus"), "Released")
		T.equal(table.concat(player.names(), ","), "DataLoadStatus")
	end)

	test("Studio: the diagnostics are mirrored as before", function()
		local world = H.world()
		local server = H.server(world, "Studio")
		local player = FakePlayer.new(USER)
		attach(server, player, true)
		server.core.load(USER)
		T.equal(player:GetAttribute("DataLoadStatus"), "Loaded")
		T.equal(player:GetAttribute("DataPortalLocked"), false)
		T.equal(type(player:GetAttribute("DataLoadDetail")), "string")
		server.core.autosaveAll()
		T.equal(player:GetAttribute("DataSaveSeq"), 1)
		T.isTrue(string.find(player:GetAttribute("DataLastSave"), "ok seq=1", 1, true) ~= nil)
		world.store:setFailing("UpdateAsync", true)
		server.core.save(USER, "Barrier")
		T.equal(player:GetAttribute("DataSaveFailures"), 1)
	end)

	test("a player who already left gets nothing and nothing errors", function()
		local listener = StatusAttributes.listener({
			getPlayer = function(): any
				return nil
			end,
			getSaveSeq = function(): number?
				return nil
			end,
			diagnostics = true,
		})
		listener({ kind = "Status", userId = USER, status = "Loaded" })
		listener({ kind = "Save", userId = USER, ok = true, reason = "Leave", seq = 2 })
	end)

	test("wiring: init.luau subscribes the listener on every server, diagnostics only in Studio", function()
		local setUp = SourceSection.between(SERVICE_FILE, "local function setUp()", "function DataService.Start()")
		local subscribe = SourceSection.at(setUp, "core.subscribe(StatusAttributes.listener(")
		local studioBranch = SourceSection.at(setUp, "if isStudio then")
		T.isTrue(subscribe ~= nil, "listener subscribed in setUp")
		T.isTrue(studioBranch ~= nil, "Studio branch found")
		T.isTrue((subscribe :: number) < (studioBranch :: number), "subscribed before (outside) the Studio branch")
		T.isTrue(SourceSection.at(setUp, "diagnostics = isStudio,") ~= nil, "diagnostics follow isStudio")
		local whole = SourceSection.between(SERVICE_FILE, "--!strict", "return DataService")
		T.equal(SourceSection.at(whole, ':SetAttribute("DataLoadStatus"'), nil, "no second writer in init.luau")
	end)
end)

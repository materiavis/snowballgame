--!strict
-- Balances are written to player attributes on every server, the totals only in Studio at
-- PlaceId 0 (ADR 0007, ADR 0008). Runs against a real CurrencyCore over DataCore, as on a live
-- server (diagnostics off) and in Studio (on). The Roblox wiring in init.luau is checked as
-- text: the mirror is connected outside the Studio branch.

local T = require("../../TestKit")
local H = require("../DataService/Harness")
local FakePlayer = require("../../helpers/FakePlayer")
local SourceSection = require("../../helpers/SourceSection")
local CurrencyConfig = require("../../../src/shared/Config/Currency")
local BalanceAttributes = require("../../../src/server/Services/CurrencyService/BalanceAttributes")
local CurrencyCore = require("../../../src/server/Services/CurrencyService/CurrencyCore")

local USER = H.USER
local SERVICE_FILE = "src/server/Services/CurrencyService/init.luau"

type Setup = { server: H.Server, currency: any, player: FakePlayer.FakePlayer, mirror: BalanceAttributes.Mirror }

local function setUp(diagnostics: boolean): Setup
	local world = H.world()
	local server = H.server(world, if diagnostics then "Studio" else "Live")
	local currency = CurrencyCore.new({
		config = CurrencyConfig :: any,
		getProfile = function(userId: number)
			return server.core.getData(userId)
		end,
		log = function() end,
	})
	local player = FakePlayer.new(USER)
	local mirror = BalanceAttributes.new({
		core = currency,
		getPlayer = function(userId: number): any
			return if userId == USER then player else nil
		end,
		diagnostics = diagnostics,
	})
	currency.subscribe(mirror.onEvent)
	-- As init.luau does on DataService.LoadStatusChanged "Loaded".
	server.core.subscribe(function(event: any)
		if event.kind == "Status" and event.status == "Loaded" then
			mirror.mirror(player, event.userId)
		end
	end)
	return { server = server, currency = currency, player = player, mirror = mirror }
end

return T.suite("CurrencyService balance attributes", function(test)
	test("live server: balances appear on load, totals do not", function()
		local s = setUp(false)
		s.server.core.load(USER)
		T.equal(s.player:GetAttribute("Coins"), 0)
		T.equal(s.player:GetAttribute("SnowCoins"), 0)
		T.equal(table.concat(s.player.names(), ","), "Coins,SnowCoins", "only balances are set")
	end)

	test("live server: every change updates the balance, a refusal leaves it", function()
		local s = setUp(false)
		s.server.core.load(USER)
		s.currency.add(USER, "Coins", 3400, "Sell")
		T.equal(s.player:GetAttribute("Coins"), 3400)
		s.currency.spend(USER, "Coins", 400, "Upgrade")
		T.equal(s.player:GetAttribute("Coins"), 3000)
		s.currency.add(USER, "SnowCoins", 12, "MatchWin")
		T.equal(s.player:GetAttribute("SnowCoins"), 12)
		local ok = s.currency.spend(USER, "Coins", 99999, "Upgrade")
		T.equal(ok, false)
		T.equal(s.player:GetAttribute("Coins"), 3000, "refused spend changes nothing")
		s.currency.reset(USER, "Coins", "Rebirth")
		T.equal(s.player:GetAttribute("Coins"), 0)
		T.equal(table.concat(s.player.names(), ","), "Coins,SnowCoins")
	end)

	test("Studio: the totals are mirrored too", function()
		local s = setUp(true)
		s.server.core.load(USER)
		s.currency.add(USER, "Coins", 500, "StudioSwitch")
		s.currency.spend(USER, "Coins", 200, "StudioSwitch")
		T.equal(s.player:GetAttribute("Coins"), 300)
		T.equal(s.player:GetAttribute("TotalCoins"), 500)
	end)

	test("a player who already left gets nothing and nothing errors", function()
		local s = setUp(false)
		s.server.core.load(USER)
		local mirror = BalanceAttributes.new({
			core = s.currency,
			getPlayer = function(): any
				return nil
			end,
			diagnostics = true,
		})
		mirror.onEvent({ kind = "Earn", userId = USER })
	end)

	test("wiring: init.luau mirrors balances on every server, totals only with the Studio tools", function()
		local setUpBody =
			SourceSection.between(SERVICE_FILE, "local function setUp()", "function CurrencyService.Start()")
		local subscribe = SourceSection.at(setUpBody, "core.subscribe(balances.onEvent)")
		local loaded = SourceSection.at(setUpBody, "DataService.LoadStatusChanged:Connect(")
		local studioBranch = SourceSection.at(setUpBody, "if studioTools then")
		T.isTrue(subscribe ~= nil and loaded ~= nil and studioBranch ~= nil, "found the wiring")
		T.isTrue((subscribe :: number) < (studioBranch :: number), "change mirror outside the Studio branch")
		T.isTrue((loaded :: number) < (studioBranch :: number), "load mirror outside the Studio branch")
		local studio = SourceSection.between(SERVICE_FILE, "local function setUpStudio()", "local function setUp()")
		T.equal(SourceSection.at(studio, "LoadStatusChanged"), nil, "no Studio-only load mirror left")
		local whole = SourceSection.between(SERVICE_FILE, "--!strict", "return CurrencyService")
		T.isTrue(SourceSection.at(whole, "diagnostics = studioTools,") ~= nil, "totals follow studioTools")
	end)
end)

--!strict
-- Wiring checks for the Roblox-facing zone modules (#39, ADR 0014), which cannot load under Lune:
-- the remotes take one bounded zone number (AC10), a paid barrier is saved at once (AC13), zone
-- changes go through BallService.EnterZone (AC5), the switches are Studio-only, and the config
-- values hold (AC1, AC8, AC11).

local fs = require("@lune/fs")
local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local FakeClock = require("../../../helpers/FakeClock")
local Section = require("../../../helpers/SourceSection")
local Schema = require("../../../../src/shared/Net/Schema")
local Registry = require("../../../../src/shared/Net/Registry")
local RateLimiter = require("../../../../src/shared/Net/RateLimiter")
local Stats = require("../../../../src/shared/Net/Stats")
local Guard = require("../../../../src/shared/Net/Guard")
local declareRemotes = require("../../../../src/shared/Net/Remotes")
local NetConfig = require("../../../../src/shared/Config/Net")
local MapConfig = require("../../../../src/shared/Config/Map")
local UpgradesConfig = require("../../../../src/shared/Config/Upgrades")
local TutorialConfig = require("../../../../src/shared/Config/Tutorial")
local ZoneUi = require("../../../../src/shared/Config/ZoneUi")

local SERVICE = "src/places/simulator/server/ZoneService/init.luau"
local BALL = "src/places/simulator/server/BallService/init.luau"

local function guarded(name: string)
	local definition = Registry.build(declareRemotes(Schema, NetConfig, UpgradesConfig, TutorialConfig))[name]
	local clock = FakeClock.new()
	local stats = Stats.new()
	local handled: { { any } } = {}
	local call = Guard.new(definition, {
		limiter = RateLimiter.new(definition.rateLimit, clock.now),
		stats = stats,
		getHandler = function()
			return function(_player: any, ...: any)
				table.insert(handled, { ... })
			end
		end,
		reportError = function() end,
	})
	return call, handled, stats
end

local function assertDeepFrozen(value: any, path: string)
	if type(value) ~= "table" then
		return
	end
	T.isTrue(table.isfrozen(value), `{path} is frozen`)
	for key, inner in value do
		assertDeepFrozen(inner, `{path}.{tostring(key)}`)
	end
end

return T.suite("ZoneService wiring (#39)", function(test)
	test("AC10: ZoneUnlock and ZoneTeleport take exactly one whole zone 1..50, rate limited", function()
		T.equal(NetConfig.Zones.MaxZone, E.Config.Zones.ZoneCount, "the technical bound is the zone count")
		for _, name in { "ZoneUnlock", "ZoneTeleport" } do
			local call, handled, stats = guarded(name)
			call({}, 2)
			T.equal(#handled, 1, `{name} accepts 2`)
			for _, args in
				{
					table.pack(0),
					table.pack(51),
					table.pack(1.5),
					table.pack("2"),
					table.pack(0 / 0),
					table.pack(math.huge),
					table.pack(nil),
					table.pack({ 2 }),
					table.pack(2, 320), -- a price on top
					{ n = 0 },
				}
			do
				-- A fresh player per call, so the schema (not the rate limit) drops it.
				call({}, table.unpack(args, 1, args.n))
			end
			T.equal(#handled, 1, `{name} drops every malformed call`)
			local burst = NetConfig.RateLimits[name].Burst
			local rateCall, rateHandled, rateStats = guarded(name)
			local player = {}
			for _ = 1, burst + 3 do
				rateCall(player, 2)
			end
			T.equal(#rateHandled, burst, `{name}: only the burst passes`)
			T.equal(rateStats:get(name).byReason.Rate, 3)
			T.equal(stats:get(name).byReason.Args, 8, `{name}: schema refusals`)
			T.equal(stats:get(name).byReason.Arity, 2, `{name}: no argument or an extra price`)
		end
	end)

	test("AC13: a successful unlock is saved at once through DataService.SaveNow", function()
		local body = Section.between(SERVICE, "local function purchase(", "local function teleport(")
		local purchaseAt = Section.at(body, "core.purchase(player.UserId, zone, reason)")
		local saveAt = Section.at(body, "DataService.SaveNow(player, SAVE_REASON)")
		T.isTrue(purchaseAt ~= nil and saveAt ~= nil and purchaseAt < saveAt, "purchase, then SaveNow")
		local failedReturn = Section.at(body, "return\n\tend")
		T.isTrue(failedReturn ~= nil and failedReturn < (saveAt :: number), "a refusal returns before saving")
	end)

	test("AC10: the handlers pass only the zone; price and coins come from the server", function()
		local text = fs.readFile(SERVICE)
		T.isTrue(string.find(text, "purchase(player, zone, REMOTE_REASON)", 1, true) ~= nil)
		T.isTrue(string.find(text, "teleport(player, zone, REMOTE_REASON)", 1, true) ~= nil)
		T.isTrue(string.find(text, "Formulas.Zones.barrierPrice(zone - 1)", 1, true) ~= nil, "missing amount")
	end)

	test("AC5: every zone change goes through BallService.EnterZone", function()
		local body = Section.between(SERVICE, "local function enterZone(", "local function moveToStart(")
		T.isTrue(Section.at(body, "BallService.EnterZone(player, zone)") ~= nil)
		local ball = Section.between(BALL, "function BallService.EnterZone(", "function BallService.PlaceAtCharacter(")
		T.isTrue(Section.at(ball, "rules.carryFraction(state.zone, state.fraction, zone)") ~= nil)
		local text = fs.readFile(SERVICE)
		T.equal(string.find(text, "BallService.SetZone", 1, true), nil, "never the fraction-keeping switch path")
	end)

	test("Studio switches and diagnostics only in Studio at PlaceId 0", function()
		local text = fs.readFile(SERVICE)
		T.isTrue(string.find(text, "local studioTools = isStudio and game.PlaceId == 0", 1, true) ~= nil)
		local _, calls = string.gsub(text, "setUpStudio%(%)", "")
		T.equal(calls, 2, "defined once and called once")
		T.isTrue(string.find(text, "if studioTools then\n\t\tsetUpStudio()", 1, true) ~= nil)
		local purchase = Section.between(SERVICE, "local function purchase(", "local function teleport(")
		T.isTrue(Section.at(purchase, "if studioTools then") ~= nil, "save diagnostics gated")
	end)

	test("AC8, AC11: the cap and the zone numbers come from Config", function()
		T.equal(E.Config.Zones.HighestOpenZone, 5)
		T.equal(E.Config.Zones.ZoneTeleportWait, 3)
		assertDeepFrozen(MapConfig, "Config.Map")
		assertDeepFrozen(ZoneUi, "Config.ZoneUi")
		local core = fs.readFile("src/places/simulator/server/ZoneService/ZoneCore.luau")
		T.isTrue(string.find(core, "config.HighestOpenZone", 1, true) ~= nil)
		T.isTrue(string.find(core, "formulas.barrierPrice(barrier)", 1, true) ~= nil)
	end)
end)

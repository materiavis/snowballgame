--!strict
-- Wiring checks of SellService and its client feedback (#38 AC8, AC9, ADR 0012), read as text:
-- no client value reaches a sale, Studio tools stay Studio-only, the ScaleAnchor lookup is
-- limited to Workspace.Map (ADR 0009), and the sale result remote is server -> client only.

local fs = require("@lune/fs")
local T = require("../../../TestKit")
local SourceSection = require("../../../helpers/SourceSection")
local Schema = require("../../../../src/shared/Net/Schema")
local Registry = require("../../../../src/shared/Net/Registry")
local declareRemotes = require("../../../../src/shared/Net/Remotes")
local NetConfig = require("../../../../src/shared/Config/Net")
local UpgradesConfig = require("../../../../src/shared/Config/Upgrades")
local TutorialConfig = require("../../../../src/shared/Config/Tutorial")
local MapConfig = require("../../../../src/shared/Config/Map")

local DIR = "src/places/simulator/server/SellService"
local INIT = `{DIR}/init.luau`
local CLIENT = "src/places/simulator/client/SaleController/init.luau"

local function code(path: string): string
	local lines = {}
	for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function allServerCode(): string
	local parts = {}
	for _, entry in fs.readDir(DIR) do
		table.insert(parts, code(`{DIR}/{entry}`))
	end
	return table.concat(parts, "\n")
end

return T.suite("SellService wiring (ADR 0012)", function(test)
	test("AC8: no client-to-server path: no handler, no server event, no invoke", function()
		local server = allServerCode()
		for _, pattern in { "NetService.handle", "OnServerEvent", "OnServerInvoke", "InvokeClient" } do
			T.equal(string.find(server, pattern, 1, true), nil, pattern)
		end
		local client = code(CLIENT)
		for _, pattern in { "FireServer", "InvokeServer" } do
			T.equal(string.find(client, pattern, 1, true), nil, `client {pattern}`)
		end
	end)

	test("AC8: SaleResult is declared, bounded and rate limited; nothing handles it on the server", function()
		local definitions = Registry.build(declareRemotes(Schema, NetConfig, UpgradesConfig, TutorialConfig))
		local remote = definitions.SaleResult
		T.isTrue(remote ~= nil, "declared")
		T.equal(remote.kind, "Event")
		T.equal(#remote.args, 1)
		T.equal(remote.rateLimit, NetConfig.RateLimits.SaleResult)
		T.isTrue((remote.args[1].check(80)), "whole coins pass")
		T.equal((remote.args[1].check(1.5)), false, "fractions fail")
		T.equal((remote.args[1].check(-1)), false, "negatives fail")
		T.equal((remote.args[1].check(NetConfig.Sale.MaxCoins * 10)), false, "too large fails")
		T.equal((remote.args[1].check("80")), false, "strings fail")
	end)

	test("AC8: the sale reads the size from BallService and only the PetMultiplier attribute", function()
		local init = code(INIT)
		T.isTrue(string.find(init, "BallService.GetSizeMetres(player)", 1, true) ~= nil, "server size")
		local _, reads = string.gsub(init, "GetAttribute%(", "")
		T.equal(reads, 1, "one attribute read")
		T.isTrue(
			string.find(init, "player:GetAttribute(SellConfig.PetMultiplierAttribute)", 1, true) ~= nil,
			"the server-written PetMultiplier"
		)
		T.isTrue(string.find(init, "UpgradeService.GetEffect(player, SELL_VALUE)", 1, true) ~= nil, "Sell value")
		T.isTrue(string.find(init, "CurrencyService.AddCoins(player, amount, reason)", 1, true) ~= nil, "coins")
	end)

	test("every bonus comes from one function, all off until 9.x / 7.11", function()
		local section = SourceSection.between(INIT, "local function activeBonusFlags(", "local core = SellCore.new")
		T.isTrue(string.find(section, "return SaleOverride.noFlags(flagNames)", 1, true) ~= nil)
		local _, calls = string.gsub(code(INIT), "activeBonusFlags%(", "")
		T.equal(calls, 2, "defined once, called once")
	end)

	test("Studio switches and diagnostics only in Studio at PlaceId 0", function()
		local init = code(INIT)
		T.isTrue(
			string.find(init, "local studioTools = isStudio and game.PlaceId == 0", 1, true) ~= nil,
			"PlaceId gate"
		)
		T.isTrue(string.find(init, "if studioTools then\n\t\tsetUpStudio()", 1, true) ~= nil, "switches gated")
		local _, binds = string.gsub(init, "SellSwitches%.bind%(", "")
		T.equal(binds, 1)
		T.isTrue(string.find(init, "if studioTools then\n\t\tlocal names", 1, true) ~= nil, "live attributes gated")
		local _, writes = string.gsub(init, "SetAttribute%(", "")
		T.equal(writes, 4, "two in the gated live block, two in setUpStudio")
	end)

	test("ADR 0009: the MAX arrow only uses ScaleAnchors below Workspace.Map", function()
		local path = "src/places/simulator/server/BallService/BallAttributes.luau"
		local section =
			SourceSection.between(path, "local function nearestAnchor(", "local function publishDiagnostics(")
		T.isTrue(string.find(section, "workspace:FindFirstChild(mapFolderName)", 1, true) ~= nil)
		T.isTrue(string.find(section, "instance:IsDescendantOf(map)", 1, true) ~= nil)
		local init = code("src/places/simulator/server/BallService/init.luau")
		T.isTrue(
			string.find(init, "BallAttributes.new(BallConfig, rules, studioTools, MapConfig.FolderName)", 1, true)
				~= nil
		)
	end)

	test("ScalePlate tag is in Config.Map", function()
		T.equal(MapConfig.Tags.ScalePlate, "ScalePlate")
		T.isTrue(table.isfrozen(MapConfig.Tags))
	end)
end)

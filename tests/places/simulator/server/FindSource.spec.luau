--!strict
-- Wiring and config checks of FindService and FindController (#40 AC9, AC10, ADR 0016), read as
-- text and from the real Config: no client value reaches a find, the remote is server -> client
-- only and bounded, the zone comes from ZoneService's shared resolver, Studio tools stay
-- Studio-only, Magnet is read at every check and every number comes from Config.

local fs = require("@lune/fs")
local T = require("../../../TestKit")
local SourceSection = require("../../../helpers/SourceSection")
local E = require("../../../helpers/Economy")
local Schema = require("../../../../src/shared/Net/Schema")
local Registry = require("../../../../src/shared/Net/Registry")
local declareRemotes = require("../../../../src/shared/Net/Remotes")
local NetConfig = require("../../../../src/shared/Config/Net")
local MapConfig = require("../../../../src/shared/Config/Map")
local Ui = require("../../../../src/shared/Config/Ui")
local PopupText = require("../../../../src/shared/PopupText")

local Finds = E.Config.Finds
local DIR = "src/places/simulator/server/FindService"
local INIT = `{DIR}/init.luau`
local CLIENT_DIR = "src/places/simulator/client/FindController"

local function code(path: string): string
	local lines = {}
	for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function allCode(dir: string): string
	local parts = {}
	for _, entry in fs.readDir(dir) do
		table.insert(parts, code(`{dir}/{entry}`))
	end
	return table.concat(parts, "\n")
end

local function collect(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

return T.suite("FindService wiring and config (ADR 0016)", function(test)
	test("AC9: no client-to-server path: no handler, no server event, no client send", function()
		local server = allCode(DIR)
		for _, pattern in { "NetService.handle", "OnServerEvent", "OnServerInvoke", "InvokeClient" } do
			T.equal(string.find(server, pattern, 1, true), nil, pattern)
		end
		local client = allCode(CLIENT_DIR)
		for _, pattern in { "FireServer", "InvokeServer" } do
			T.equal(string.find(client, pattern, 1, true), nil, `client {pattern}`)
		end
		local _, fires = string.gsub(server, "FireClient%(", "")
		T.equal(fires, 1, "one send, to one player: each sees only their own finds")
		T.isTrue(string.find(server, "FireAllClients", 1, true) == nil)
	end)

	test("AC9: FindUpdate is declared, server -> client, bounded and rate limited", function()
		local remote = Registry.build(declareRemotes(Schema, NetConfig, E.Config.Upgrades)).FindUpdate
		T.isTrue(remote ~= nil, "declared")
		T.equal(remote.kind, "Event")
		T.equal(#remote.args, 4)
		T.equal(remote.rateLimit, NetConfig.RateLimits.FindUpdate)
		local action, slot, id, position = remote.args[1], remote.args[2], remote.args[3], remote.args[4]
		for _, name in { "Spawn", "Remove", "Collect", "ClearBall", "Reset" } do
			T.isTrue((action.check(name)), name)
		end
		T.equal((action.check("Give")), false, "unknown action")
		T.isTrue((slot.check(nil)), "slot is optional")
		T.equal((slot.check(0)), false)
		T.equal((slot.check(1.5)), false)
		T.equal((slot.check(NetConfig.Finds.MaxSlot + 1)), false)
		T.equal((id.check(string.rep("x", NetConfig.Finds.MaxIdLength + 1))), false)
		T.equal((position.check("here")), false)
		for findId in Finds.Items do
			T.isTrue(#findId <= NetConfig.Finds.MaxIdLength, `{findId} fits the bound`)
			T.isTrue((id.check(findId)), findId)
		end
	end)

	test("AC9: pickup inputs are server-side: ball part, IsHeld, Magnet effect, unlocked zone", function()
		local section = SourceSection.between(INIT, "local function pickup(", "function FindService.Start()")
		T.isTrue(string.find(section, "BallService.GetBallPart(player)", 1, true) ~= nil, "server view of the ball")
		T.isTrue(string.find(section, "UpgradeService.GetEffect(player, MAGNET)", 1, true) ~= nil, "Magnet")
		T.isTrue(string.find(section, "BallService.IsHeld(player)", 1, true) ~= nil, "owner at the ball")
		local init = code(INIT)
		T.isTrue(string.find(init, "ZoneService.IsUnlocked(player, zone)", 1, true) ~= nil, "unlocked zone")
		T.isTrue(string.find(init, "SellService.AddFindValue(player, value)", 1, true) ~= nil, "value into the ball")
		T.isTrue(string.find(init, 'local MAGNET = "magnet"', 1, true) ~= nil)
	end)

	test("AC6: Magnet is read at every pickup check, never cached; it is no longer locked", function()
		local section = SourceSection.between(INIT, "local function pickup(", "function FindService.Start()")
		T.isTrue(string.find(section, "local magnet = UpgradeService.GetEffect(player, MAGNET)", 1, true) ~= nil)
		local init = code(INIT)
		local _, reads = string.gsub(init, "UpgradeService%.GetEffect%(", "")
		T.equal(reads, 1, "read in one place: the pickup check")
		T.equal(E.Config.Upgrades.Locked.magnet, nil)
	end)

	test("ADR 0009 / 0014: the zone of a point comes from ZoneService's shared resolver", function()
		local server = allCode(DIR)
		T.isTrue(string.find(server, "zoneOf = ZoneService.ZoneOfInstance", 1, true) ~= nil)
		T.equal(string.find(server, "ZoneIndexAttribute)", 1, true), nil, "no own ZoneIndex read")
		T.equal(string.find(server, "StationRules.new", 1, true), nil, "no second resolver")
		local points = code(`{DIR}/FindPoints.luau`)
		T.isTrue(string.find(points, "instance:IsDescendantOf(map)", 1, true) ~= nil, "Workspace.Map scope")
		T.isTrue(string.find(points, "StationRules.warning(tag", 1, true) ~= nil, "the MapContract warning")
		T.equal(MapConfig.Tags.FindPoint, "FindPoint")
	end)

	test("Studio switches and diagnostics only in Studio at PlaceId 0", function()
		local init = code(INIT)
		T.isTrue(string.find(init, "local studioTools = isStudio and game.PlaceId == 0", 1, true) ~= nil)
		T.isTrue(string.find(init, "if studioTools then\n\t\tsetUpStudio()", 1, true) ~= nil, "switches gated")
		local _, binds = string.gsub(init, "FindStudio%.bind%(", "")
		T.equal(binds, 1)
		local _, forces = string.gsub(init, "core%.setForce%(", "")
		T.equal(forces, 2, "force only from setUpStudio and the gated activate")
		local activate = SourceSection.between(INIT, "local function activate(", "local magnetSent")
		T.isTrue(string.find(activate, "if studioTools then\n\t\tcore.setForce", 1, true) ~= nil)
	end)

	test("only FindService writes sim.collection.finds and sim.titles", function()
		local files = {}
		collect("src", files)
		for _, path in files do
			local text = code(path)
			-- SellCore keeps its own `finds` table of ball values; only code that reaches the
			-- profile's collection counts here.
			local collectionWrite = string.find(text, "collection", 1, true) ~= nil
				and string.find(text, "finds%[[%w_]+%]%s*=") ~= nil
			local writes = collectionWrite or string.find(text, "titles%[[%w_]+%]%s*=") ~= nil
			if writes then
				T.equal(path, `{DIR}/FindCore.luau`, `{path} writes the collection or titles`)
			end
		end
	end)

	test("AC10: Config.Finds holds every number; the logic has no tuning literal", function()
		T.equal(Finds.SpawnInterval, 20)
		T.equal(Finds.SecretChance, 1 / 2000)
		T.equal(Finds.LegendaryFromZoneInWorld, 6)
		for _, path in { `{DIR}/FindCore.luau`, `{DIR}/FindPoints.luau`, INIT, `{CLIENT_DIR}/init.luau` } do
			local lineNumber = 0
			for line in string.gmatch(code(path) .. "\n", "([^\n]*)\n") do
				lineNumber += 1
				-- Strings may hold digits ("%.4f", "Find_{slot}"); only bare literals count. Halving a
				-- diameter into a radius is geometry, not a tuning value.
				local bare = string.gsub(string.gsub(line, '"[^"]*"', '""'), "`[^`]*`", "``")
				bare = string.gsub(bare, "/ 2%f[^%d.]", "")
				for literal in string.gmatch(bare, "%f[%w_.]%d+%.?%d*%f[^%w_.]") do
					T.isTrue(literal == "0" or literal == "1", `{path}:{lineNumber} has the literal {literal}`)
				end
			end
		end
	end)

	test("catalogue: every Alps rarity has its find; names from the concept appendix", function()
		local names = {
			Common = "Pine Cone",
			Uncommon = "Chocolate Bar",
			Rare = "Edelweiss",
			Epic = "Rock Crystal",
			Legendary = "Golden Cowbell",
		}
		for rarity, name in names do
			local id = Finds.ByWorld[1][rarity]
			T.equal(Finds.Items[id].Name, name, rarity)
			T.equal(Finds.Items[id].Rarity, rarity)
			T.equal(Finds.Items[id].World, 1)
		end
		local secret = Finds.Items[Finds.SecretFind]
		T.equal(secret.Name, "Yeti Footprint")
		T.equal(secret.Rarity, "Secret")
		T.equal(secret.World, nil, "every world")
		T.isTrue(Finds.BallEffects[Finds.SecretTitle] ~= nil, "the secret title gives a ball effect")
		T.isTrue(Finds.TitleNames[Finds.SecretTitle] ~= nil)
		for id, item in Finds.Items do
			T.isTrue(E.Rarity.isRarity(item.Rarity), `{id} has a rarity`)
		end
	end)

	test("7.7 pop-ups: exactly the very rare finds have one, with the rarity in words and symbols", function()
		for id, item in Finds.Items do
			local rare = Finds.PopupRarities[item.Rarity] == true
			T.equal(item.PopupKey ~= nil, rare, `{id} pop-up`)
			if item.PopupKey then
				T.isTrue((PopupText.check(item.PopupKey, {}, Ui, NetConfig.Popup)), `{item.PopupKey} is a pop-up text`)
				local text = Ui.Text[item.PopupKey]
				local info = E.Rarity.get(item.Rarity)
				T.isTrue(string.find(text, info.symbol, 1, true) ~= nil, `{id}: symbol (8.5)`)
				T.isTrue(string.find(text, info.name, 1, true) ~= nil, `{id}: rarity name`)
				T.isTrue(string.find(text, item.Name, 1, true) ~= nil, `{id}: find name`)
			end
		end
		for _, rarity in { "Common", "Uncommon", "Rare" } do
			T.equal(Finds.PopupRarities[rarity], nil, `{rarity} shows no pop-up`)
		end
		T.isTrue((PopupText.check(Finds.TitlePopupKey, {}, Ui, NetConfig.Popup)))
		T.isTrue(string.find(Ui.Text[Finds.TitlePopupKey], Finds.TitleNames[Finds.SecretTitle], 1, true) ~= nil)
	end)
end)

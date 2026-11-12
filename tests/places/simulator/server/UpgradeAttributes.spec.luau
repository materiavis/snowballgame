--!strict
-- Upgrade player attributes (#36, ADR 0010): on a live server only `Upgrade<Id>Level` appears;
-- Studio diagnostics add `Upgrade<Id>Effect`. Plus source checks of the Roblox wiring: the
-- levels are mirrored outside the Studio branch, the switches only inside it, the remote has a
-- handler, and MovementService stays the only writer of Humanoid.WalkSpeed.

local fs = require("@lune/fs")
local T = require("../../../TestKit")
local E = require("../../../helpers/Economy")
local FakePlayer = require("../../../helpers/FakePlayer")
local LevelAttributes = require("../../../../src/places/simulator/server/UpgradeService/LevelAttributes")
local UpgradeAttributes = require("../../../../src/shared/UpgradeAttributes")

local SERVICE = "src/places/simulator/server/UpgradeService/init.luau"
local Upgrades = E.Config.Upgrades

local function mirrorFor(levels: { [string]: any }, diagnostics: boolean)
	return LevelAttributes.new({
		ids = Upgrades.Order,
		level = function(_userId: number, id: string): number?
			return levels[id]
		end,
		effect = E.Upgrades.effect,
		levelName = UpgradeAttributes.level,
		effectName = UpgradeAttributes.effect,
		diagnostics = diagnostics,
	})
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

return T.suite("UpgradeService attributes and wiring", function(test)
	test("a live server writes only the five Level attributes", function()
		local player = FakePlayer.new(1)
		mirrorFor({ growth = 3, walkSpeed = 100, magnet = 0, sellValue = 7, stability = 50 }, false).mirror(player, 1)
		T.equal(
			table.concat(player.names(), ","),
			"UpgradeGrowthLevel,UpgradeMagnetLevel,UpgradeSellValueLevel,UpgradeStabilityLevel,UpgradeWalkSpeedLevel"
		)
		T.equal(player:GetAttribute("UpgradeWalkSpeedLevel"), 100)
		T.equal(player:GetAttribute("UpgradeGrowthLevel"), 3)
	end)

	test("Studio diagnostics add the effect at that level", function()
		local player = FakePlayer.new(1)
		mirrorFor({ growth = 0, walkSpeed = 50, magnet = 100, sellValue = 100, stability = 100 }, true).mirror(
			player,
			1
		)
		T.equal(player:GetAttribute("UpgradeWalkSpeedEffect"), 24)
		T.equal(player:GetAttribute("UpgradeGrowthEffect"), 40)
		T.equal(player:GetAttribute("UpgradeMagnetEffect"), 24)
		T.equal(player:GetAttribute("UpgradeSellValueEffect"), 6)
		T.near(player:GetAttribute("UpgradeStabilityEffect"), 0.02, 1e-12)
	end)

	test("a level the profile cannot give removes its attribute", function()
		local player = FakePlayer.new(1)
		local levels: { [string]: any } = { growth = 4, walkSpeed = 1, magnet = 0, sellValue = 0, stability = 0 }
		mirrorFor(levels, true).mirror(player, 1)
		levels.growth = nil
		mirrorFor(levels, true).mirror(player, 1)
		T.equal(player:GetAttribute("UpgradeGrowthLevel"), nil)
		T.equal(player:GetAttribute("UpgradeGrowthEffect"), nil)
		T.equal(player:GetAttribute("UpgradeWalkSpeedLevel"), 1)
	end)

	test("the service mirrors levels outside the Studio branch and binds switches only inside it", function()
		local source = fs.readFile(SERVICE)
		T.isTrue(string.find(source, "local studioTools = isStudio and game.PlaceId == 0", 1, true) ~= nil)
		T.isTrue(string.find(source, "diagnostics = studioTools", 1, true) ~= nil, "effects only in Studio")
		local setUpStart = string.find(source, "local function setUp()", 1, true) :: number
		local setUp = string.sub(source, setUpStart)
		T.isTrue(string.find(setUp, "core.subscribe(onEvent", 1, true) ~= nil, "levels after every change")
		T.isTrue(string.find(setUp, 'status == "Loaded"', 1, true) ~= nil, "levels on load")
		T.isTrue(string.find(setUp, "NetService.handle(REMOTE", 1, true) ~= nil, "the remote has a handler")
		T.isTrue(string.find(setUp, "if studioTools then\n\t\tsetUpStudio(stands)", 1, true) ~= nil)
		local studioStart = string.find(source, "local function setUpStudio", 1, true) :: number
		T.isTrue(studioStart < setUpStart, "switch bindings live in setUpStudio")
		local studio = string.sub(source, studioStart, setUpStart)
		local outside = string.sub(source, 1, studioStart) .. string.sub(source, setUpStart)
		for _, switch in { "BUY_SWITCH", "SET_LEVEL_SWITCH", "TEST_STANDS_SWITCH" } do
			T.isTrue(string.find(studio, `({switch}`, 1, true) ~= nil, `{switch} bound in setUpStudio`)
			T.equal(string.find(outside, `({switch}`, 1, true), nil, `{switch} not bound outside it`)
		end
	end)

	test("the remote handler passes only the validated id; level and price come from the server", function()
		local source = fs.readFile(SERVICE)
		T.isTrue(
			string.find(
				source,
				"NetService.handle(REMOTE, function(player: Player, id: string)\n\t\tcore.purchase(player.UserId, id, REMOTE_REASON)\n\tend)",
				1,
				true
			) ~= nil
		)
	end)

	test("MovementService is the only writer of Humanoid.WalkSpeed", function()
		local files = {}
		collect("src", files)
		local writers = {}
		for _, path in files do
			for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
				if string.find(line .. " ", "%.WalkSpeed%s*[%+%-%*/]?=[^=]") then
					table.insert(writers, path)
				end
			end
		end
		T.equal(table.concat(writers, ","), "src/places/simulator/server/MovementService.luau")
	end)

	test("only UpgradeService writes sim.upgrades", function()
		local files = {}
		collect("src", files)
		local allowed = "src/places/simulator/server/UpgradeService/"
		local offenders = {}
		for _, path in files do
			if string.sub(path, 1, #allowed) ~= allowed then
				for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
					if string.find(line .. " ", "upgrades%[[^%]]+%]%s*[%+%-%*/]?=[^=]") then
						table.insert(offenders, path)
					end
				end
			end
		end
		T.equal(#offenders, 0, table.concat(offenders, ", "))
	end)
end)

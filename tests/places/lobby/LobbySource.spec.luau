--!strict
-- Source checks for the Lobby code (issue #37 AC7, AC9; ADR 0015): the client has no way to ask
-- for a portal travel or a chest reward (no remote, no FireServer), the portal travels only
-- through TravelService and checks DataService.IsPortalLocked, the chest grants only through
-- CurrencyService, and every Studio switch is behind the Studio + PlaceId 0 gate.

local fs = require("@lune/fs")
local T = require("../../TestKit")

local ROOT = "src/places/lobby"

local function collect(dir: string, out: { [string]: string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			out[path] = fs.readFile(path)
		end
	end
end

local function sources(): { [string]: string }
	local out = {}
	collect(ROOT, out)
	return out
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return T.suite("Lobby source rules", function(test)
	test("AC9: no remote in the Lobby code: the client cannot request a portal or a reward", function()
		local files = sources()
		local count = 0
		for path, text in files do
			count += 1
			for _, needle in { "FireServer", "InvokeServer", "OnServerEvent", "OnServerInvoke", "NetService.handle" } do
				T.equal(has(text, needle), false, `{path} uses {needle}`)
			end
			T.equal(has(text, 'Instance.new("RemoteEvent")'), false, path)
			T.equal(has(text, 'Instance.new("RemoteFunction")'), false, path)
		end
		T.isTrue(count >= 15, `found the Lobby files ({count})`)
	end)

	test("AC2/AC7: the portal checks the 6.5 lock and travels only through TravelService", function()
		local text = fs.readFile(`{ROOT}/server/PortalService/init.luau`)
		T.isTrue(has(text, "DataService.IsPortalLocked(player)"))
		T.isTrue(has(text, "TravelService.IsTraveling(player)"))
		T.isTrue(has(text, "TravelService.ToSimulator(player)"))
		T.equal(has(text, "TeleportService"), false)
		-- The position comes from the server's own character, never from a client value.
		T.isTrue(has(text, "LobbyMap.rootOf(player)"))
	end)

	test("AC6: the chest grants only through CurrencyService and saves through DataService", function()
		local text = fs.readFile(`{ROOT}/server/GroupChestService/init.luau`)
		T.isTrue(has(text, "CurrencyService.AddCoins(player, amount, REASON)"))
		T.isTrue(has(text, "CurrencyService.AddSnowCoins(player, amount, REASON)"))
		T.isTrue(has(text, "DataService.SaveNow(player, REASON)"))
		T.isTrue(has(text, "pcall"), "the group web call is protected")
	end)

	test("every Studio switch is gated by Studio and PlaceId 0", function()
		for path, text in sources() do
			if has(text, "ServerScriptService:SetAttribute(") then
				T.isTrue(
					has(text, "RunService:IsStudio() and game.PlaceId == 0"),
					`{path} defines a switch without the gate`
				)
			end
		end
		local studio = fs.readFile(`{ROOT}/server/LobbyStudioService/init.luau`)
		T.isTrue(has(studio, "if not studioTools then\n\t\treturn"), "LobbyStudioService does nothing live")
	end)

	test("the Lobby skeleton is replaced by real services", function()
		T.equal(fs.isFile(`{ROOT}/server/LobbySkeletonService.luau`), false)
	end)
end)

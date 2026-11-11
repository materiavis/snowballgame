--!strict
-- Structural checks (ADR 0003, ADR 0010, CLAUDE.md §6 and §9): PlaceId 0 never reaches
-- MemoryStoreService or TeleportService, PresenceStore is the only module that names
-- MemoryStoreService, TravelService the only one that names TeleportService, and every message
-- key TravelCore sends has a text in Config.Travel. The Roblox services cannot run under Lune,
-- so their wiring is checked as text.

local fs = require("@lune/fs")
local T = require("../../TestKit")
local StoreProvider = require("../../../src/server/Services/PresenceStore/StoreProvider")
local TravelConfig = require("../../../src/shared/Config/Travel")

local PRESENCE_DIR = "src/server/Services/PresenceStore/"
local TRAVEL_DIR = "src/server/Services/TravelService/"

local function collect(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(out, (string.gsub(path, "\\", "/")))
		end
	end
end

local function count(text: string, needle: string): number
	local found, from = 0, 1
	while true do
		local at = string.find(text, needle, from, true)
		if at == nil then
			return found
		end
		found += 1
		from = at + #needle
	end
end

local function within(path: string, dir: string): boolean
	return string.sub(path, 1, #dir) == dir
end

return T.suite("TravelService and PresenceStore only paths", function(test)
	test("PlaceId 0 picks the fake MemoryStore without calling the real service", function()
		local realCalls = 0
		local fake = {}
		local provider, mode = StoreProvider.select(0, function()
			realCalls += 1
			return {}
		end, function()
			return fake
		end)
		T.equal(mode, "Fake")
		T.equal(provider, fake)
		T.equal(realCalls, 0)
		local _, liveMode = StoreProvider.select(42, function()
			return {}
		end, function()
			error("no fake on a published Place")
		end)
		T.equal(liveMode, "Real")
	end)

	test("PresenceStore fetches MemoryStoreService only inside the StoreProvider choice", function()
		local source = fs.readFile(PRESENCE_DIR .. "init.luau")
		local fetch = 'GetService("MemoryStoreService")'
		T.equal(count(source, fetch), 1, "fetched in exactly one place")
		local selectAt = string.find(source, "StoreProvider.select(game.PlaceId, function()", 1, true)
		local fetchAt = string.find(source, fetch, 1, true)
		local fakeAt = string.find(source, "FakeMemoryStore.newService(", 1, true)
		T.isTrue(selectAt ~= nil and fetchAt ~= nil and fakeAt ~= nil, "expected wiring present")
		T.isTrue((selectAt :: number) < (fetchAt :: number), "fetch is inside the real-service callback")
		T.isTrue((fetchAt :: number) < (fakeAt :: number), "callback ends before the fake factory")
		local mapAt = string.find(source, ":GetHashMap(", 1, true)
		T.isTrue(mapAt ~= nil and mapAt > (fakeAt :: number), "the map comes from the chosen provider")
	end)

	test("no module outside PresenceStore mentions MemoryStoreService", function()
		local files: { string } = {}
		collect("src", files)
		T.isTrue(#files > 0)
		for _, path in files do
			if not within(path, PRESENCE_DIR) then
				local source = fs.readFile(path)
				T.equal(count(source, "MemoryStoreService"), 0, `{path} names MemoryStoreService`)
				T.equal(count(source, ":GetHashMap("), 0, `{path} opens a hash map`)
				T.equal(count(source, ":GetSortedMap("), 0, `{path} opens a sorted map`)
				T.equal(count(source, ":GetQueue("), 0, `{path} opens a queue`)
			end
		end
	end)

	test("TeleportService is fetched once, after the PlaceId 0 stub check, and only in TravelService", function()
		local source = fs.readFile(TRAVEL_DIR .. "init.luau")
		local fetch = 'GetService("TeleportService")'
		T.equal(count(source, fetch), 1)
		local stubAt = string.find(source, "if isStub then\n\t\treturn StubTeleporter.new(", 1, true)
		local fetchAt = string.find(source, fetch, 1, true)
		T.isTrue(stubAt ~= nil and fetchAt ~= nil and (stubAt :: number) < (fetchAt :: number), "stub first")
		T.isTrue(string.find(source, "local isStub = game.PlaceId == 0", 1, true) ~= nil)

		local files: { string } = {}
		collect("src", files)
		for _, path in files do
			if not within(path, TRAVEL_DIR) then
				T.equal(count(fs.readFile(path), "TeleportService"), 0, `{path} names TeleportService`)
			end
		end
		for _, name in
			{ "TravelCore", "LoadFailReturn", "Destinations", "ServerChoice", "StubTeleporter", "StudioTools" }
		do
			local child = fs.readFile(`{TRAVEL_DIR}{name}.luau`)
			T.equal(count(child, 'GetService("TeleportService")'), 0, `{name} never fetches TeleportService`)
		end
	end)

	test("every message key TravelCore and LoadFailReturn send has a German text", function()
		local keys = 0
		for _, name in { "TravelCore", "LoadFailReturn" } do
			local source = fs.readFile(`{TRAVEL_DIR}{name}.luau`)
			for key in string.gmatch(source, 'notify%(userId, "(%w+)"%)') do
				keys += 1
				T.equal(type(TravelConfig.Messages[key]), "string", `{name}: Messages.{key}`)
			end
		end
		T.isTrue(keys >= 9, "found the notify calls")
	end)
end)

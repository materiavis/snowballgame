--!strict
-- PlaceId 0 never touches real DataStores (issue #26 AC5, CLAUDE.md §9), and no module
-- outside DataService reaches DataStoreService (CLAUDE.md §6). The source checks are
-- structural: the Roblox service cannot run under Lune, so its wiring is checked as text.

local fs = require("@lune/fs")
local T = require("../../TestKit")
local StoreProvider = require("../../../src/server/Services/DataService/StoreProvider")

local DATA_SERVICE_DIR = "src/server/Services/DataService/"
local SERVICE_FILE = DATA_SERVICE_DIR .. "init.luau"

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

return T.suite("DataService store selection", function(test)
	test("PlaceId 0 picks the fake without calling the real service", function()
		local realCalls = 0
		local fake = { IsFake = true }
		local provider, mode = StoreProvider.select(0, function()
			realCalls += 1
			return {}
		end, function()
			return fake
		end)
		T.equal(mode, "Fake")
		T.equal(provider, fake)
		T.equal(realCalls, 0, "real DataStoreService never requested")
	end)

	test("a published PlaceId picks the real service", function()
		local real = {}
		local provider, mode = StoreProvider.select(123, function()
			return real
		end, function()
			error("fake must not be built for a published Place")
		end)
		T.equal(mode, "Real")
		T.equal(provider, real)
	end)

	test("DataService fetches DataStoreService only inside the StoreProvider choice", function()
		local source = fs.readFile(SERVICE_FILE)
		T.equal(count(source, 'GetService("DataStoreService")'), 1, "fetched in exactly one place")
		local selectAt = string.find(source, "StoreProvider.select(game.PlaceId, function()", 1, true)
		local fetchAt = string.find(source, 'GetService("DataStoreService")', 1, true)
		local fakeAt = string.find(source, "end, FakeStore.newService)", 1, true)
		T.isTrue(selectAt ~= nil and fetchAt ~= nil and fakeAt ~= nil, "expected wiring present")
		T.isTrue((selectAt :: number) < (fetchAt :: number), "fetch is inside the real-service callback")
		T.isTrue((fetchAt :: number) < (fakeAt :: number), "callback ends before the fake factory")
		local firstStore = string.find(source, ":GetDataStore(", 1, true) or math.huge
		local firstOrdered = string.find(source, ":GetOrderedDataStore(", 1, true) or math.huge
		T.isTrue(math.min(firstStore, firstOrdered) > (fakeAt :: number), "stores come from the chosen provider")
	end)

	test("no module outside DataService mentions DataStoreService or opens a DataStore", function()
		local files: { string } = {}
		collect("src", files)
		T.isTrue(#files > 0, "found source files")
		for _, path in files do
			local normalized = string.gsub(path, "\\", "/")
			if string.sub(normalized, 1, #DATA_SERVICE_DIR) == DATA_SERVICE_DIR then
				continue
			end
			local source = fs.readFile(path)
			for _, needle in { "DataStoreService", ":GetDataStore(", ":GetOrderedDataStore(" } do
				T.equal(count(source, needle), 0, `{normalized} uses {needle}`)
			end
		end
	end)
end)

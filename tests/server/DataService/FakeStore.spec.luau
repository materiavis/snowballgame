--!strict
-- The fake behaves like a DataStore where the code depends on it: copies, cancelled
-- updates, rejected values and injected faults.

local T = require("../../TestKit")
local FakeStore = require("../../../src/server/Services/DataService/FakeStore")

return T.suite("DataService/FakeStore", function(test)
	test("values are copied in and out", function()
		local store = FakeStore.new()
		local value = { a = { b = 1 } }
		store:SetAsync("k", value)
		value.a.b = 2
		T.equal(store:GetAsync("k").a.b, 1)
		store:GetAsync("k").a.b = 3
		T.equal(store:GetAsync("k").a.b, 1)
	end)

	test("UpdateAsync returning nil writes nothing", function()
		local store = FakeStore.new()
		store:SetAsync("k", 1)
		T.equal(
			store:UpdateAsync("k", function()
				return nil
			end),
			nil
		)
		T.equal(store:GetAsync("k"), 1)
		T.equal(
			store:UpdateAsync("k", function(old)
				return old + 1
			end),
			2
		)
	end)

	test("rejects values a DataStore cannot encode", function()
		local store = FakeStore.new()
		T.throws(function()
			store:SetAsync("k", { [1] = true, [3] = true })
		end, "sparse")
		T.throws(function()
			store:SetAsync("k", { [1] = true, x = true })
		end, "mixes")
		T.throws(function()
			store:SetAsync("k", { n = 0 / 0 })
		end, "finite")
		T.throws(function()
			store:SetAsync("k", { f = print })
		end, "function")
		store:SetAsync("k", { list = { 1, 2, 3 }, set = { ["1"] = true } })
	end)

	test("failNext and setFailing throw like an outage and count calls", function()
		local store = FakeStore.new()
		store:failNext("GetAsync", 2)
		T.throws(function()
			store:GetAsync("k")
		end, "injected")
		T.throws(function()
			store:GetAsync("k")
		end, "injected")
		T.equal(store:GetAsync("k"), nil)
		store:setFailing("UpdateAsync", true)
		T.throws(function()
			store:UpdateAsync("k", function()
				return 1
			end)
		end, "injected")
		T.equal(store:peek("k"), nil, "failed update wrote nothing")
		T.equal(store:callCount("GetAsync"), 3)
	end)

	test("ordered stores keep whole numbers and sort descending", function()
		local store = FakeStore.newOrdered()
		store:SetAsync("1", 5)
		store:SetAsync("2", 9)
		store:SetAsync("3", 7)
		T.throws(function()
			store:SetAsync("4", 1.5)
		end, "whole number")
		local page = store:GetSortedAsync(false, 2):GetCurrentPage()
		T.equal(#page, 2)
		T.equal(page[1].key, "2")
		T.equal(page[2].key, "3")
	end)

	test("the fake service returns the same store per name", function()
		local service = FakeStore.newService()
		T.equal(service:GetDataStore("a"), service:GetDataStore("a"))
		T.isTrue(service:GetDataStore("a") ~= service:GetDataStore("b"))
		T.equal(service:GetOrderedDataStore("a"), service:GetOrderedDataStore("a"))
	end)
end)

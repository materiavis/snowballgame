--!strict
-- In-memory stand-in for DataStoreService, used whenever game.PlaceId == 0 (Studio test
-- Places, CLAUDE.md §9) and by the headless tests. It copies values in and out and rejects
-- what a real DataStore would reject (functions, NaN, mixed or sparse tables), so code that
-- passes here does not depend on sharing tables with the store.
--
-- Fault injection: failNext(op, count) and setFailing(op, on) make the named method throw,
-- like a DataStore outage. op is the method name, e.g. "UpdateAsync".
-- Pure, no requires and no Roblox globals.

local FakeStore = {}

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[key] = copy(inner)
	end
	return out
end

-- Throws with the path of the first value a DataStore could not encode as JSON.
local function checkSavable(value: any, path: string, seen: { [any]: boolean })
	local kind = type(value)
	if kind == "boolean" or kind == "nil" then
		return
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error(`FakeStore: {path} is not a finite number`, 0)
		end
	elseif kind == "string" then
		if utf8.len(value) == nil then
			error(`FakeStore: {path} is not valid UTF-8`, 0)
		end
	elseif kind == "table" then
		if seen[value] then
			error(`FakeStore: {path} is a cyclic table`, 0)
		end
		seen[value] = true
		local count, numberKeys, maxIndex = 0, 0, 0
		for key, inner in value do
			count += 1
			if type(key) == "number" then
				numberKeys += 1
				if key % 1 ~= 0 or key < 1 then
					error(`FakeStore: {path} has a non-index number key {key}`, 0)
				end
				maxIndex = math.max(maxIndex, key)
			elseif type(key) ~= "string" then
				error(`FakeStore: {path} has a {type(key)} key`, 0)
			end
			checkSavable(inner, `{path}.{tostring(key)}`, seen)
		end
		if numberKeys > 0 and (numberKeys ~= count or maxIndex ~= count) then
			error(`FakeStore: {path} mixes keys or is a sparse array`, 0)
		end
		seen[value] = nil
	else
		error(`FakeStore: {path} is a {kind}, which a DataStore cannot store`, 0)
	end
end

local function newFaults()
	local pending: { [string]: number } = {}
	local always: { [string]: boolean } = {}
	local calls: { [string]: number } = {}
	local faults = {}

	-- Counts the call and throws if a fault is armed for op.
	function faults.enter(op: string)
		calls[op] = (calls[op] or 0) + 1
		if always[op] then
			error(`FakeStore: injected {op} failure`, 0)
		end
		local remaining = pending[op]
		if remaining and remaining > 0 then
			pending[op] = remaining - 1
			error(`FakeStore: injected {op} failure`, 0)
		end
	end

	function faults.failNext(_self: any, op: string, count: number?)
		pending[op] = (pending[op] or 0) + (count or 1)
	end

	function faults.setFailing(_self: any, op: string, on: boolean)
		always[op] = on
	end

	function faults.callCount(_self: any, op: string): number
		return calls[op] or 0
	end

	return faults
end

-- GlobalDataStore subset: GetAsync, SetAsync, UpdateAsync, RemoveAsync.
function FakeStore.new(): any
	local values: { [string]: any } = {}
	local faults = newFaults()
	local store: any = {
		failNext = faults.failNext,
		setFailing = faults.setFailing,
		callCount = faults.callCount,
	}

	function store:GetAsync(key: string): any
		faults.enter("GetAsync")
		return copy(values[key])
	end

	function store:SetAsync(key: string, value: any)
		faults.enter("SetAsync")
		checkSavable(value, key, {})
		values[key] = copy(value)
	end

	-- Like Roblox: the transform gets a copy of the stored value; returning nil cancels the
	-- write and UpdateAsync returns nil.
	function store:UpdateAsync(key: string, transform: (any, any) -> any): any
		faults.enter("UpdateAsync")
		local updated = transform(copy(values[key]), nil)
		if updated == nil then
			return nil
		end
		checkSavable(updated, key, {})
		values[key] = copy(updated)
		return copy(updated)
	end

	function store:RemoveAsync(key: string): any
		faults.enter("RemoveAsync")
		local old = values[key]
		values[key] = nil
		return copy(old)
	end

	-- Test and Studio helper, not part of the DataStore API: reads without counting or faults.
	function store:peek(key: string): any
		return copy(values[key])
	end

	return store
end

-- OrderedDataStore subset: SetAsync, GetAsync, RemoveAsync, GetSortedAsync (first page only).
function FakeStore.newOrdered(): any
	local values: { [string]: number } = {}
	local faults = newFaults()
	local store: any = {
		failNext = faults.failNext,
		setFailing = faults.setFailing,
		callCount = faults.callCount,
	}

	function store:SetAsync(key: string, value: any)
		faults.enter("SetAsync")
		if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value >= 2 ^ 53 then
			error(`FakeStore: ordered value for {key} must be a whole number in [0, 2^53), got {value}`, 0)
		end
		values[key] = value
	end

	function store:GetAsync(key: string): number?
		faults.enter("GetAsync")
		return values[key]
	end

	function store:RemoveAsync(key: string): number?
		faults.enter("RemoveAsync")
		local old = values[key]
		values[key] = nil
		return old
	end

	function store:GetSortedAsync(ascending: boolean, pageSize: number): any
		faults.enter("GetSortedAsync")
		local entries = {}
		for key, value in values do
			table.insert(entries, { key = key, value = value })
		end
		table.sort(entries, function(a, b)
			if a.value == b.value then
				return a.key < b.key
			end
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local page = {}
		for index = 1, math.min(pageSize, #entries) do
			page[index] = entries[index]
		end
		return {
			IsFinished = true,
			GetCurrentPage = function(_self: any)
				return page
			end,
		}
	end

	return store
end

-- DataStoreService subset. Returns the same store for the same name for the lifetime of the
-- service, so a player who leaves and rejoins a Studio server finds their saved profile.
function FakeStore.newService(): any
	local stores: { [string]: any } = {}
	local ordered: { [string]: any } = {}
	local service: any = { IsFake = true }

	function service:GetDataStore(name: string): any
		stores[name] = stores[name] or FakeStore.new()
		return stores[name]
	end

	function service:GetOrderedDataStore(name: string): any
		ordered[name] = ordered[name] or FakeStore.newOrdered()
		return ordered[name]
	end

	return service
end

FakeStore.checkSavable = function(value: any)
	checkSavable(value, "value", {})
end

return table.freeze(FakeStore)

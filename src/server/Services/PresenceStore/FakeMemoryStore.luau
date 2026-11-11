--!strict
-- In-memory stand-in for MemoryStoreService hash maps, used at PlaceId 0 and in the headless
-- tests (ADR 0003: every store is a fake in Studio). Pure, no requires: the clock is injected.
-- Values are copied in and out like the real service, entries expire after their TTL, and
-- setFailing makes every call throw like an outage.

-- MemoryStore allows at most 45 days per entry.
local MAX_EXPIRATION = 45 * 24 * 60 * 60

export type FakeMap = {
	GetAsync: (self: FakeMap, key: string) -> any,
	SetAsync: (self: FakeMap, key: string, value: any, expiration: number) -> boolean,
	RemoveAsync: (self: FakeMap, key: string) -> (),
	setFailing: (self: FakeMap, failing: boolean) -> (),
	size: (self: FakeMap) -> number,
}

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[copy(key)] = copy(inner)
	end
	return out
end

local function checkValue(value: any)
	local kind = type(value)
	if kind == "function" or kind == "userdata" or kind == "thread" then
		error(`FakeMemoryStore: cannot store a {kind}`, 3)
	end
	if kind == "number" and value ~= value then
		error("FakeMemoryStore: cannot store NaN", 3)
	end
	if kind == "table" then
		for key, inner in value do
			if type(key) ~= "string" and type(key) ~= "number" then
				error("FakeMemoryStore: table keys must be strings or numbers", 3)
			end
			checkValue(inner)
		end
	end
end

local FakeMemoryStore = {}

function FakeMemoryStore.newMap(now: () -> number): FakeMap
	local entries: { [string]: { value: any, expires: number } } = {}
	local failing = false
	local map = {}

	local function guard(key: any)
		if failing then
			error("FakeMemoryStore: injected failure", 3)
		end
		if type(key) ~= "string" or key == "" then
			error("FakeMemoryStore: key must be a non-empty string", 3)
		end
	end

	function map.GetAsync(_self: FakeMap, key: string): any
		guard(key)
		local entry = entries[key]
		if entry == nil then
			return nil
		end
		if now() >= entry.expires then
			entries[key] = nil
			return nil
		end
		return copy(entry.value)
	end

	function map.SetAsync(_self: FakeMap, key: string, value: any, expiration: number): boolean
		guard(key)
		if type(expiration) ~= "number" or expiration <= 0 or expiration > MAX_EXPIRATION then
			error(`FakeMemoryStore: expiration must be 0 < s <= {MAX_EXPIRATION}`, 2)
		end
		checkValue(value)
		entries[key] = { value = copy(value), expires = now() + expiration }
		return true
	end

	function map.RemoveAsync(_self: FakeMap, key: string)
		guard(key)
		entries[key] = nil
	end

	function map.setFailing(_self: FakeMap, value: boolean)
		failing = value
	end

	-- Live (not expired) entries, for tests.
	function map.size(_self: FakeMap): number
		local count = 0
		for _, entry in entries do
			if now() < entry.expires then
				count += 1
			end
		end
		return count
	end

	return map :: any
end

-- Mirrors MemoryStoreService:GetHashMap; the same name returns the same map.
function FakeMemoryStore.newService(now: () -> number)
	local maps: { [string]: FakeMap } = {}
	local service = {}
	function service.GetHashMap(_self: any, name: string): FakeMap
		local map = maps[name]
		if map == nil then
			map = FakeMemoryStore.newMap(now)
			maps[name] = map
		end
		return map
	end
	return service
end

return table.freeze(FakeMemoryStore)

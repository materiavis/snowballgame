--!strict
-- Cross-server presence and private-server mapping on one MemoryStore hash map (ADR 0003
-- "Cross-server ephemeral state", ADR 0010). Pure, no requires: the map, wait and log are
-- injected, so `lune run tests` runs it against FakeMemoryStore.
--
-- Keys (prefixes in Config.Travel):
--   user_<userId>                 { world, jobId }        which Simulator server a user is on
--   server_<jobId>                { world, count }        players on that Simulator server
--   private_<privateKey>_<world>  { accessCode, privateServerId }  reserved server of a private context
--   reserved_<privateServerId>    privateKey              reverse lookup for that reserved server
--
-- Everything here is best effort: a failed call returns nil/false and is logged. Losing it only
-- loses the friend preference or opens a second reserved server, never progress. Values read
-- back are checked, because a MemoryStore value is shared with every server.

export type UserEntry = { world: number, jobId: string }
export type ServerEntry = { world: number, count: number }
export type Reserved = { accessCode: string, privateServerId: string }

export type Deps = {
	map: any, -- MemoryStoreHashMap or FakeMemoryStore map
	wait: (seconds: number) -> (),
	log: (level: "info" | "warn", message: string) -> (),
	config: {
		PresenceTtl: number,
		PrivateMappingTtl: number,
		FriendLookupMax: number,
		PresenceAttempts: number,
		PresenceRetryDelay: number,
		UserKeyPrefix: string,
		ServerKeyPrefix: string,
		PrivateKeyPrefix: string,
		ReservedKeyPrefix: string,
	},
}

local function isWhole(value: any, min: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value < math.huge
end

local function isText(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local PresenceCore = {}

function PresenceCore.new(deps: Deps)
	local config = deps.config
	local map = deps.map
	local store = {}

	-- Runs one map call with a few spaced attempts. Returns ok and the call's result.
	local function call(what: string, fn: () -> any): (boolean, any)
		local lastError: any = nil
		for attempt = 1, config.PresenceAttempts do
			local ok, result = pcall(fn)
			if ok then
				return true, result
			end
			lastError = result
			if attempt < config.PresenceAttempts then
				deps.wait(config.PresenceRetryDelay)
			end
		end
		deps.log("warn", `{what} failed: {tostring(lastError)}`)
		return false, nil
	end

	local function userKey(userId: number): string
		return config.UserKeyPrefix .. tostring(userId)
	end

	local function serverKey(jobId: string): string
		return config.ServerKeyPrefix .. jobId
	end

	local function privateKey(key: string, world: number): string
		return `{config.PrivateKeyPrefix}{key}_{world}`
	end

	function store.setUser(userId: number, world: number, jobId: string): boolean
		local ok = call(`set presence of {userId}`, function()
			return map:SetAsync(userKey(userId), { world = world, jobId = jobId }, config.PresenceTtl)
		end)
		return ok
	end

	function store.removeUser(userId: number): boolean
		local ok = call(`remove presence of {userId}`, function()
			return map:RemoveAsync(userKey(userId))
		end)
		return ok
	end

	function store.getUser(userId: number): UserEntry?
		local ok, value = call(`read presence of {userId}`, function()
			return map:GetAsync(userKey(userId))
		end)
		if ok and type(value) == "table" and isWhole(value.world, 1) and isText(value.jobId) then
			return { world = value.world, jobId = value.jobId }
		end
		return nil
	end

	function store.setServer(jobId: string, world: number, count: number): boolean
		local ok = call(`set server {jobId}`, function()
			return map:SetAsync(serverKey(jobId), { world = world, count = count }, config.PresenceTtl)
		end)
		return ok
	end

	function store.removeServer(jobId: string): boolean
		local ok = call(`remove server {jobId}`, function()
			return map:RemoveAsync(serverKey(jobId))
		end)
		return ok
	end

	function store.getServer(jobId: string): ServerEntry?
		local ok, value = call(`read server {jobId}`, function()
			return map:GetAsync(serverKey(jobId))
		end)
		if ok and type(value) == "table" and isWhole(value.world, 1) and isWhole(value.count, 0) then
			return { world = value.world, count = value.count }
		end
		return nil
	end

	-- One refresh of a public Simulator server: its player count and every player on it.
	-- Returns how many writes worked.
	function store.publishServer(jobId: string, world: number, userIds: { number }): number
		local written = if store.setServer(jobId, world, #userIds) then 1 else 0
		for _, userId in userIds do
			if store.setUser(userId, world, jobId) then
				written += 1
			end
		end
		return written
	end

	-- The first friend (in list order, at most FriendLookupMax) on a server of this world with
	-- fewer than maxPlayers players. A server without a live record counts as unknown and is
	-- skipped, so a stale friend entry never sends anyone to a dead or full server.
	function store.findFriendServer(
		friendIds: { number },
		world: number,
		maxPlayers: number,
		excludeJobId: string?
	): (string?, number?)
		local checked = 0
		for _, friendId in friendIds do
			if checked >= config.FriendLookupMax then
				break
			end
			checked += 1
			local entry = store.getUser(friendId)
			if entry and entry.world == world and entry.jobId ~= excludeJobId then
				local server = store.getServer(entry.jobId)
				if server and server.world == world and server.count < maxPlayers then
					return entry.jobId, friendId
				end
			end
		end
		return nil, nil
	end

	function store.getReserved(key: string, world: number): Reserved?
		local ok, value = call(`read private mapping {key}`, function()
			return map:GetAsync(privateKey(key, world))
		end)
		if ok and type(value) == "table" and isText(value.accessCode) and isText(value.privateServerId) then
			return { accessCode = value.accessCode, privateServerId = value.privateServerId }
		end
		return nil
	end

	-- Stores both directions, so the reserved server can find out which private context it
	-- belongs to (its game.PrivateServerId is the only thing it knows about itself).
	function store.setReserved(key: string, world: number, accessCode: string, privateServerId: string): boolean
		local forward = call(`set private mapping {key}`, function()
			return map:SetAsync(
				privateKey(key, world),
				{ accessCode = accessCode, privateServerId = privateServerId },
				config.PrivateMappingTtl
			)
		end)
		local reverse = call(`set reserved owner {privateServerId}`, function()
			return map:SetAsync(config.ReservedKeyPrefix .. privateServerId, key, config.PrivateMappingTtl)
		end)
		return forward and reverse
	end

	function store.getPrivateKey(privateServerId: string): string?
		local ok, value = call(`read reserved owner {privateServerId}`, function()
			return map:GetAsync(config.ReservedKeyPrefix .. privateServerId)
		end)
		if ok and isText(value) then
			return value
		end
		return nil
	end

	return table.freeze(store)
end

return table.freeze(PresenceCore)

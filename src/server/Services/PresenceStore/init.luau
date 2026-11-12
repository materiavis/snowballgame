--!strict
-- PresenceStore: the only module that touches MemoryStoreService (ADR 0003 "Persistence" and
-- "Cross-server ephemeral state", ADR 0010). Presence of users on Simulator servers (friend
-- preference, concept 5.6) and the private server -> reserved Simulator server mapping.
-- The logic is in the pure PresenceCore; this file only picks the backend.
--
-- At game.PlaceId == 0 the backend is FakeMemoryStore and MemoryStoreService is never fetched.
-- Not a service (no Start), so the loader requires it but does not count it; it sets up on
-- the first call. Later MemoryStore users (portal counts #37, matchmaking 7.14) extend this
-- module instead of opening their own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TravelConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Travel")) :: any
local FakeMemoryStore = require(script:WaitForChild("FakeMemoryStore"))
local PresenceCore = require(script:WaitForChild("PresenceCore"))
local StoreProvider = require(script:WaitForChild("StoreProvider"))

type StoreMode = "Fake" | "Real"

local PresenceStore = {}

local core: any = nil
local storeMode: StoreMode = "Fake"

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[PresenceStore] {message}`)
	elseif RunService:IsStudio() then
		print(`[PresenceStore] {message}`)
	end
end

local function ensure(): any
	if core then
		return core
	end
	local service, mode = StoreProvider.select(game.PlaceId, function()
		return game:GetService("MemoryStoreService")
	end, function()
		return FakeMemoryStore.newService(os.clock)
	end)
	storeMode = mode
	core = PresenceCore.new({
		map = service:GetHashMap(TravelConfig.PresenceMapName),
		wait = function(seconds)
			task.wait(seconds)
		end,
		log = log,
		config = TravelConfig,
	})
	log("info", `store={storeMode} (PlaceId {game.PlaceId}) ttl={TravelConfig.PresenceTtl}s`)
	return core
end

function PresenceStore.SetUser(userId: number, world: number, jobId: string): boolean
	return ensure().setUser(userId, world, jobId)
end

function PresenceStore.RemoveUser(userId: number): boolean
	return ensure().removeUser(userId)
end

function PresenceStore.GetUser(userId: number): any
	return ensure().getUser(userId)
end

function PresenceStore.SetServer(jobId: string, world: number, count: number): boolean
	return ensure().setServer(jobId, world, count)
end

function PresenceStore.RemoveServer(jobId: string): boolean
	return ensure().removeServer(jobId)
end

function PresenceStore.PublishServer(jobId: string, world: number, userIds: { number }): number
	return ensure().publishServer(jobId, world, userIds)
end

function PresenceStore.FindFriendServer(
	friendIds: { number },
	world: number,
	maxPlayers: number,
	excludeJobId: string?
): (string?, number?)
	return ensure().findFriendServer(friendIds, world, maxPlayers, excludeJobId)
end

function PresenceStore.GetReserved(key: string, world: number): any
	return ensure().getReserved(key, world)
end

function PresenceStore.SetReserved(key: string, world: number, accessCode: string, privateServerId: string): boolean
	return ensure().setReserved(key, world, accessCode, privateServerId)
end

function PresenceStore.GetPrivateKey(privateServerId: string): string?
	return ensure().getPrivateKey(privateServerId)
end

function PresenceStore.GetStoreMode(): StoreMode
	ensure()
	return storeMode
end

return PresenceStore

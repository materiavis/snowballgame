--!strict
-- Studio playtest switches for TravelService (ADR 0010). TravelService only calls this when
-- RunService:IsStudio() and game.PlaceId == 0; live servers never set or read these attributes.
-- Attribute names are the playtest contract. All switches live on ServerScriptService and are
-- set from the server command bar.
--
--   TravelStudioTrigger (string)       intent for the first player (group intents: everyone),
--                                      e.g. "Portal"; resets itself to "".
--   TravelFailTeleport (bool | number) true: every stub teleport fails; a number n: the next n fail.
--   TravelStudioFriendJobId (string)   non-empty: a fake online friend on that Simulator server.
--   TravelStudioFriendWorld (number)   the world that fake friend is in (default 1).
--   TravelStudioFriendServerFull (bool) the fake friend's server is full.

local ServerScriptService = game:GetService("ServerScriptService")

local TRIGGER = "TravelStudioTrigger"
local FAIL_TELEPORT = "TravelFailTeleport"
local FRIEND_JOB = "TravelStudioFriendJobId"
local FRIEND_WORLD = "TravelStudioFriendWorld"
local FRIEND_FULL = "TravelStudioFriendServerFull"

-- UserId of the fake friend. Negative like Studio's test players, so it is never a real account.
local STUDIO_FRIEND_ID = -999

export type Presence = {
	SetUser: (userId: number, world: number, jobId: string) -> boolean,
	SetServer: (jobId: string, world: number, count: number) -> boolean,
}

local StudioTools = {}

StudioTools.FRIEND_ID = STUDIO_FRIEND_ID

local function default(name: string, value: any)
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, value)
	end
end

-- Creates the switches and calls onTrigger(intent) whenever the trigger is set.
function StudioTools.setUp(onTrigger: (intent: string) -> ())
	default(TRIGGER, "")
	default(FAIL_TELEPORT, false)
	default(FRIEND_JOB, "")
	default(FRIEND_WORLD, 1)
	default(FRIEND_FULL, false)
	ServerScriptService:GetAttributeChangedSignal(TRIGGER):Connect(function()
		local intent = ServerScriptService:GetAttribute(TRIGGER)
		if type(intent) ~= "string" or intent == "" then
			return
		end
		ServerScriptService:SetAttribute(TRIGGER, "")
		task.spawn(onTrigger, intent)
	end)
end

-- One stub teleport attempt asks whether it should fail. A number counts down.
function StudioTools.takeTeleportFailure(): boolean
	local value = ServerScriptService:GetAttribute(FAIL_TELEPORT)
	if value == true then
		return true
	end
	if type(value) == "number" and value >= 1 then
		ServerScriptService:SetAttribute(FAIL_TELEPORT, value - 1)
		return true
	end
	return false
end

-- The fake friend list. Writes the friend's presence into the fake PresenceStore first, so the
-- real friend-preference code path runs against it.
function StudioTools.friendIds(presence: Presence, maxPlayers: number): { number }
	local jobId = ServerScriptService:GetAttribute(FRIEND_JOB)
	if type(jobId) ~= "string" or jobId == "" then
		return {}
	end
	local world = ServerScriptService:GetAttribute(FRIEND_WORLD)
	if type(world) ~= "number" or world < 1 or world % 1 ~= 0 then
		world = 1
	end
	local full = ServerScriptService:GetAttribute(FRIEND_FULL) == true
	presence.SetUser(STUDIO_FRIEND_ID, world :: number, jobId)
	presence.SetServer(jobId, world :: number, if full then maxPlayers else 1)
	return { STUDIO_FRIEND_ID }
end

return table.freeze(StudioTools)

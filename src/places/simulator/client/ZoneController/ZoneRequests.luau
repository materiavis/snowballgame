--!strict
-- The only zone requests a client sends (#39, ADR 0014): a zone number on ZoneUnlock or
-- ZoneTeleport. Never a price, a size or a position; ZoneService decides everything again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")) :: any

local UNLOCK_REMOTE = "ZoneUnlock"
local TELEPORT_REMOTE = "ZoneTeleport"

local ZoneRequests = {}

function ZoneRequests.unlock(zone: number)
	local remote = Net.waitForRemote(UNLOCK_REMOTE) :: RemoteEvent
	remote:FireServer(zone)
end

function ZoneRequests.teleport(zone: number)
	local remote = Net.waitForRemote(TELEPORT_REMOTE) :: RemoteEvent
	remote:FireServer(zone)
end

return table.freeze(ZoneRequests)

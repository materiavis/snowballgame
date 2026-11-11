--!strict
-- Live teleports for published Places (ADR 0010). TeleportService is passed in by
-- TravelService, which fetches it only when game.PlaceId ~= 0, so Studio never reaches it.
--
-- TeleportAsync can fail at once (it throws) or later (TeleportInitFailed). Success shows as
-- the player leaving this server. No teleport data is sent: the destination reads everything
-- it needs from the profile and from MemoryStore (ADR 0003), never from the client.

local Players = game:GetService("Players")

export type Settings = { TeleportTimeout: number, TeleportPoll: number }

local RealTeleporter = {}

function RealTeleporter.new(teleportService: TeleportService, settings: Settings)
	local pending: { [Player]: (reason: string) -> () } = {}
	local teleporter = {}

	teleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		local report = pending[player]
		if report then
			report(`{result.Name}: {message}`)
		end
	end)

	function teleporter.teleport(userId: number, dest: any, target: any, _info: any): (boolean, string?)
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			return true, nil -- already gone
		end
		local options = Instance.new("TeleportOptions")
		if target.server == "Friend" and target.jobId then
			options.ServerInstanceId = target.jobId
		elseif target.server == "Reserved" and target.accessCode then
			options.ReservedServerAccessCode = target.accessCode
		end

		local failure: string? = nil
		pending[player] = function(reason)
			failure = reason
		end
		local ok, err = pcall(function()
			teleportService:TeleportAsync(dest.placeId, { player }, options)
		end)
		if not ok then
			pending[player] = nil
			return false, `Error: {err}`
		end
		local deadline = os.clock() + settings.TeleportTimeout
		while failure == nil and player.Parent == Players and os.clock() < deadline do
			task.wait(settings.TeleportPoll)
		end
		pending[player] = nil
		if failure then
			return false, failure
		end
		if player.Parent ~= Players then
			return true, nil
		end
		return false, "Timeout"
	end

	function teleporter.reserve(placeId: number): (boolean, string?, string?)
		local ok, accessCode, privateServerId = pcall(function()
			return teleportService:ReserveServer(placeId)
		end)
		if not ok then
			return false, tostring(accessCode), nil
		end
		return true, accessCode, privateServerId
	end

	return table.freeze(teleporter)
end

return table.freeze(RealTeleporter)

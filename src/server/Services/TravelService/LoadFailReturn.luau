--!strict
-- Load failure outside the Lobby (ADR 0003 "Load failure", ADR 0006 "Loading", ADR 0010): after
-- Config.Travel.LoadFailuresBeforeLobby failed DataService loads the player sees a message and
-- is sent back to the Lobby. No lock is held while a load fails, so nothing is saved or
-- released. In the Lobby nothing happens here: it shows its hint and locks the portals (6.5).
-- Pure, no requires. Uses TravelCore's deps and its busy flags, events and helpers, so a load
-- failure return and a normal travel never run at the same time for one player.

local LoadFailReturn = {}

local INTENT = "LoadFailReturn"

-- deps: the TravelCore.Deps table; core: the TravelCore instance built from it.
function LoadFailReturn.new(deps: any, core: any)
	local config = deps.config
	local destinations = deps.destinations
	local failures: { [number]: number } = {}
	local returned: { [number]: boolean } = {}
	local tracker = {}

	local function returnToLobby(userId: number)
		local function stillFailing(): boolean
			return deps.isPresent(userId) and deps.data.getStatus(userId) ~= "Loaded"
		end
		deps.notify(userId, "LoadFailedReturn")
		core.emit(userId, "Returning", INTENT, `load failed, back to the Lobby in {config.LoadFailReturnDelay}s`)
		deps.wait(config.LoadFailReturnDelay)
		local dest, why = destinations.resolve(INTENT, nil)
		if dest and dest.placeId == 0 and not deps.allowUnpublished then
			dest, why = nil, "Lobby is not published (Config.Places)"
		end
		if dest == nil then
			deps.log("warn", `{INTENT} for {deps.nameOf(userId)} impossible: {why}`)
			core.emit(userId, "Failed", INTENT, why or "NoDestination")
			return
		end
		local target = { server = "Public" }
		local players = `{deps.nameOf(userId)}({userId})`
		deps.log("info", `{INTENT} from={deps.role} to={core.describeDest(dest)} server=Public players={players}`)
		for attempt = 1, config.TeleportAttempts do
			if not stillFailing() then
				core.emit(userId, "Done", INTENT, "Recovered")
				return
			end
			local ok, reason = deps.teleport(userId, dest, target, core.infoFor(INTENT, attempt, players))
			if ok then
				returned[userId] = true
				core.emit(userId, "Done", INTENT, core.describeDest(dest))
				return
			end
			if attempt < config.TeleportAttempts then
				local delay = core.backoff(attempt)
				deps.notify(userId, "TeleportRetry")
				core.emit(userId, "Waiting", INTENT, `teleport failed ({reason}), retry in {delay}s`)
				deps.wait(delay)
			end
		end
		deps.notify(userId, "TeleportFailed")
		core.emit(userId, "Failed", INTENT, "TeleportFailed")
		failures[userId] = 0 -- the next failed loads start another round
	end

	-- Feed every DataService load status change here.
	function tracker.onLoadStatus(userId: number, status: string)
		if not destinations.allowedHere(INTENT) then
			return
		end
		if status == "Loaded" then
			failures[userId] = nil
			returned[userId] = nil
			return
		end
		if status ~= "Failed" then
			return
		end
		local count = (failures[userId] or 0) + 1
		failures[userId] = count
		-- After a successful return (Studio stub: the player stays) wait for a load or a rejoin.
		if count < config.LoadFailuresBeforeLobby or returned[userId] or not core.claim(userId, INTENT) then
			return
		end
		deps.spawn(function()
			returnToLobby(userId)
			core.release(userId)
		end)
	end

	-- The player left this server.
	function tracker.forget(userId: number)
		failures[userId] = nil
		returned[userId] = nil
	end

	return table.freeze(tracker)
end

return table.freeze(LoadFailReturn)

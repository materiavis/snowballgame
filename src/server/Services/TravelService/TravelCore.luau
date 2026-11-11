--!strict
-- Travel flow between Places (concept 5.6, 6.5; ADR 0003, ADR 0006 "Teleport", ADR 0010):
-- save and release -> teleport -> on failure take the lock back, message, automatic retry.
-- Pure, no requires and no Roblox globals. DataService, the teleporter, server choice,
-- messages, waits and spawning are injected, so `lune run tests` plays every failure case
-- against DataCore and the fake store.
--
-- Outcomes of one player's travel: Done, Refused, SaveFailed, TeleportFailed, Lost, Left.
-- The load-failure return to the Lobby is LoadFailReturn, built on this core.

export type State = "Refused" | "Saving" | "Teleporting" | "Waiting" | "Returning" | "Done" | "Failed" | "Lost" | "Left"

export type Event = { userId: number, state: State, intent: string, detail: string }

export type Info = { intent: string, from: string, attempt: number, attempts: number, players: string }

export type Deps = {
	role: string,
	destinations: any, -- Destinations.new(...)
	choice: { choose: (userId: number, dest: any, options: any) -> (any, string?) },
	describeTarget: (target: any) -> string,
	data: {
		prepare: (userId: number) -> (boolean, string?),
		resume: (userId: number) -> (boolean, string?),
		getStatus: (userId: number) -> string?,
		getProfile: (userId: number) -> any,
	},
	-- Yields until the teleport worked (the player left) or failed: false and a reason such as
	-- "GameFull: ...", "Timeout" or "Simulated".
	teleport: (userId: number, dest: any, target: any, info: Info) -> (boolean, string?),
	notify: (userId: number, key: string) -> (),
	kick: (userId: number, message: string) -> (),
	isPresent: (userId: number) -> boolean,
	nameOf: (userId: number) -> string,
	wait: (seconds: number) -> (),
	spawn: (fn: () -> ()) -> (),
	log: (level: "info" | "warn", message: string) -> (),
	-- Studio stub only: PlaceId 0 placeholders are valid destinations, and after a "successful"
	-- teleport the player is still here, so the session is resumed for the next test.
	allowUnpublished: boolean,
	stayAfterSuccess: boolean,
	config: {
		SaveAttempts: number,
		SaveRetryDelay: number,
		TeleportAttempts: number,
		TeleportRetryBase: number,
		TeleportRetryFactor: number,
		TeleportRetryMax: number,
		ResumeAttempts: number,
		ResumeRetryDelay: number,
		LoadFailuresBeforeLobby: number, -- LoadFailReturn
		LoadFailReturnDelay: number, -- LoadFailReturn
		Messages: { [string]: string },
	},
}

local function startsWith(text: string?, prefix: string): boolean
	return type(text) == "string" and string.sub(text, 1, #prefix) == prefix
end

local TravelCore = {}

function TravelCore.new(deps: Deps)
	local config = deps.config
	local destinations = deps.destinations
	local busy: { [number]: string } = {}
	local listeners: { (event: Event) -> () } = {}
	local core = {}

	local function emit(userId: number, state: State, intent: string, detail: string)
		local event: Event = { userId = userId, state = state, intent = intent, detail = detail }
		for _, listener in listeners do
			local ok, err = pcall(listener, event)
			if not ok then
				deps.log("warn", `listener errored: {err}`)
			end
		end
	end

	local function refuse(userId: number, intent: string, reason: string): string
		deps.log("info", `{intent} for {deps.nameOf(userId)} refused: {reason}`)
		emit(userId, "Refused", intent, reason)
		return "Refused"
	end

	local function backoff(attempt: number): number
		return math.min(config.TeleportRetryBase * config.TeleportRetryFactor ^ (attempt - 1), config.TeleportRetryMax)
	end

	local function infoFor(intent: string, attempt: number, players: string): Info
		return {
			intent = intent,
			from = deps.role,
			attempt = attempt,
			attempts = config.TeleportAttempts,
			players = players,
		}
	end

	local function describeDest(dest: any): string
		if dest.role == "Simulator" then
			return `Simulator world={dest.world} zone={dest.zone} placeId={dest.placeId}`
		end
		return `{dest.role} placeId={dest.placeId}`
	end

	-- Save and release with retries (6.5 "Speichern schlägt fehl"). On false the lock is still
	-- held (or the session is gone) and the player stays.
	local function save(userId: number, intent: string): (boolean, string)
		for attempt = 1, config.SaveAttempts do
			if not deps.isPresent(userId) then
				return false, "Left"
			end
			emit(userId, "Saving", intent, `save {attempt}/{config.SaveAttempts}`)
			local ok, why = deps.data.prepare(userId)
			if ok then
				return true, "Saved"
			end
			if why == "NotLoaded" then
				deps.notify(userId, "NotReady")
				return false, "NotLoaded"
			end
			if why ~= "StoreError" and why ~= "Error" then
				-- LockLost, Stale, Missing: DataService marked the session lost and kicked.
				return false, "Lost"
			end
			deps.log("warn", `{intent}: save for {deps.nameOf(userId)} failed ({why}), {attempt}/{config.SaveAttempts}`)
			if attempt < config.SaveAttempts then
				deps.notify(userId, "SaveRetry")
				emit(userId, "Waiting", intent, `save failed, retry in {config.SaveRetryDelay}s`)
				deps.wait(config.SaveRetryDelay)
			end
		end
		deps.notify(userId, "SaveFailed")
		return false, "SaveFailed"
	end

	-- The teleport failed after the release: take the lock back. A store error is retried; if
	-- the lock cannot be taken back the player is sent to rejoin (their state up to the save is
	-- stored). Any other refusal means DataService already marked the session lost and kicked.
	local function resume(userId: number, intent: string): boolean
		for attempt = 1, config.ResumeAttempts do
			local ok, why = deps.data.resume(userId)
			if ok then
				return true
			end
			if not startsWith(why, "StoreError") then
				deps.log("warn", `{intent}: resume for {deps.nameOf(userId)} refused ({why}); session lost`)
				return false
			end
			if attempt < config.ResumeAttempts then
				deps.wait(config.ResumeRetryDelay)
			end
		end
		deps.log("warn", `{intent}: could not take the lock back for {deps.nameOf(userId)}; asking them to rejoin`)
		deps.notify(userId, "ResumeFailed")
		deps.kick(userId, config.Messages.ResumeFailed)
		return false
	end

	-- One player's attempts against a fixed destination. Returns the outcome.
	local function run(userId: number, intent: string, dest: any, target: any, players: string): string
		local attempts = config.TeleportAttempts
		for attempt = 1, attempts do
			local saved, why = save(userId, intent)
			if not saved then
				local state: State = if why == "Lost" then "Lost" elseif why == "Left" then "Left" else "Failed"
				emit(userId, state, intent, why)
				return why
			end
			emit(
				userId,
				"Teleporting",
				intent,
				`{describeDest(dest)} server={deps.describeTarget(target)} {attempt}/{attempts}`
			)
			local ok, reason = deps.teleport(userId, dest, target, infoFor(intent, attempt, players))
			if ok then
				if deps.stayAfterSuccess and not resume(userId, intent) then
					emit(userId, "Lost", intent, "stub resume failed")
					return "Lost"
				end
				emit(userId, "Done", intent, `{describeDest(dest)} server={deps.describeTarget(target)}`)
				return "Done"
			end
			deps.log("warn", `{intent}: teleport of {deps.nameOf(userId)} failed ({reason}), {attempt}/{attempts}`)
			if not deps.isPresent(userId) then
				emit(userId, "Left", intent, "left after a failed teleport")
				return "Left"
			end
			if not resume(userId, intent) then
				emit(userId, "Lost", intent, "lock not taken back")
				return "Lost"
			end
			if target.server == "Friend" and startsWith(reason, "GameFull") then
				-- The friend's server filled up meanwhile: any other server of that world (6.5).
				target = { server = "Public" }
			end
			if attempt < attempts then
				deps.notify(userId, "TeleportRetry")
				local delay = backoff(attempt)
				emit(userId, "Waiting", intent, `teleport failed ({reason}), retry in {delay}s`)
				deps.wait(delay)
			end
		end
		deps.notify(userId, "TeleportFailed")
		emit(userId, "Failed", intent, "TeleportFailed")
		return "TeleportFailed"
	end

	-- Checks shared by single and group travel. Returns the destination or nil and the reason.
	local function check(userId: number, intent: string): (any, string?)
		if not destinations.isIntent(intent) then
			return nil, "UnknownIntent"
		end
		if intent == "LoadFailReturn" then
			return nil, "LoadFailReturn only starts from a load failure"
		end
		if not destinations.allowedHere(intent) then
			return nil, `{intent} is not valid from {deps.role}`
		end
		if busy[userId] then
			return nil, `already travelling ({busy[userId]})`
		end
		if deps.data.getStatus(userId) ~= "Loaded" then
			deps.notify(userId, "NotReady")
			return nil, "NotLoaded"
		end
		local dest, why, note = destinations.resolve(intent, deps.data.getProfile(userId))
		if dest == nil then
			return nil, why
		end
		if note then
			deps.log("warn", `{intent} for {deps.nameOf(userId)}: {note}`)
		end
		if dest.placeId == 0 and not deps.allowUnpublished then
			return nil, `{describeDest(dest)} is not published (Config.Places)`
		end
		return dest, nil
	end

	function core.subscribe(listener: (event: Event) -> ())
		table.insert(listeners, listener)
	end

	function core.isBusy(userId: number): boolean
		return busy[userId] ~= nil
	end

	-- One player (Portal, WorldGate, LobbyButton, ToLobby). Yields until the travel ends.
	function core.travel(userId: number, intent: string, options: any): string
		local dest, why = check(userId, intent)
		if dest == nil then
			return refuse(userId, intent, why :: string)
		end
		if dest.group then
			return refuse(userId, intent, "group intent; use travelGroup")
		end
		busy[userId] = intent
		local target, chooseWhy = deps.choice.choose(userId, dest, options)
		local outcome
		if target == nil then
			deps.notify(userId, "TeleportFailed")
			emit(userId, "Failed", intent, chooseWhy or "NoServer")
			outcome = "TeleportFailed"
		else
			local players = `{deps.nameOf(userId)}({userId})`
			deps.log(
				"info",
				`{intent} from={deps.role} to={describeDest(dest)} server={deps.describeTarget(target)} players={players}`
			)
			outcome = run(userId, intent, dest, target, players)
		end
		busy[userId] = nil
		return outcome
	end

	-- A group onto one server (MatchStart, Replay). Players that cannot travel are refused one
	-- by one; the rest share one target and travel in parallel. Returns "Started" or "Refused".
	function core.travelGroup(userIds: { number }, intent: string, options: any): string
		local ready: { number } = {}
		local dest: any = nil
		for _, userId in userIds do
			local playerDest, why = check(userId, intent)
			if playerDest == nil then
				refuse(userId, intent, why :: string)
			elseif not playerDest.group then
				refuse(userId, intent, "not a group intent; use travel")
			else
				dest = playerDest
				busy[userId] = intent
				table.insert(ready, userId)
			end
		end
		if #ready == 0 then
			return "Refused"
		end
		local target, why = deps.choice.choose(ready[1], dest, options)
		if target == nil then
			for _, userId in ready do
				deps.notify(userId, "TeleportFailed")
				emit(userId, "Failed", intent, why or "NoServer")
				busy[userId] = nil
			end
			return "Refused"
		end
		local names = {}
		for _, userId in ready do
			table.insert(names, `{deps.nameOf(userId)}({userId})`)
		end
		local players = table.concat(names, ",")
		deps.log(
			"info",
			`{intent} from={deps.role} to={describeDest(dest)} server={deps.describeTarget(target)} players={players}`
		)
		for _, userId in ready do
			deps.spawn(function()
				run(userId, intent, dest, table.clone(target), players)
				busy[userId] = nil
			end)
		end
		return "Started"
	end

	-- For LoadFailReturn, which shares this core's busy flags, events and helpers. claim marks
	-- the player as travelling unless something else already does.
	function core.claim(userId: number, intent: string): boolean
		if busy[userId] then
			return false
		end
		busy[userId] = intent
		return true
	end

	function core.release(userId: number)
		busy[userId] = nil
	end

	core.emit = emit
	core.backoff = backoff
	core.describeDest = describeDest
	core.infoFor = infoFor

	return table.freeze(core)
end

return table.freeze(TravelCore)

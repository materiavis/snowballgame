--!strict
-- Player profile sessions: load with session lock, save, release, teleport hand-off, erase
-- (ADR 0003 "Data model and failure behaviour", ADR 0006).
-- Pure, no requires and no Roblox globals: the store, clocks, JobId, kick, logging and the
-- LockRecord transforms are injected, so two cores sharing one fake store can play two
-- servers in `lune run tests`. The lock and saveSeq rules themselves live in LockRecord.

export type Status = "Loading" | "Loaded" | "Failed" | "Lost" | "Teleported" | "Released"

export type Event = {
	kind: "Status" | "Save",
	userId: number,
	status: Status?,
	detail: string?,
	ok: boolean?,
	reason: string?,
	seq: number?,
}

export type Deps = {
	store: any, -- GlobalDataStore or FakeStore
	records: any, -- the LockRecord module
	jobId: string,
	now: () -> number, -- wall clock in seconds, shared by all servers (os.time live)
	wait: (seconds: number) -> (),
	retry: { run: (fn: () -> any) -> (boolean, any) },
	schema: { newProfile: () -> any, prepare: (data: any) -> (any, string?) },
	kick: (userId: number, message: string) -> (),
	log: (level: "info" | "warn", message: string) -> (),
	-- Studio fault switch: returning true makes the store call of that purpose throw.
	injectFault: ((purpose: "Load" | "Save") -> boolean)?,
	boards: { removeUser: (userId: number) -> (boolean, string?) }?,
	config: {
		LockTimeout: number,
		LockRetryInterval: number,
		LoadRetryInterval: number,
		SaveQueuePoll: number,
		ProfileKeyPrefix: string,
		LockLostKickMessage: string,
	},
}

type Session = {
	userId: number,
	key: string,
	status: Status,
	data: any, -- nil until the lock is held
	saveSeq: number, -- seq of the record as this server last read or wrote it
	highestSeq: number, -- highest seq this server ever tried to write
	saving: boolean,
	cancelled: boolean, -- the player left; finish and release
	pendingRelease: boolean, -- release failed; autosave retries it
}

type LoadHook = (userId: number, data: any) -> ()

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[key] = deepCopy(inner)
	end
	return out
end

local DataCore = {}

function DataCore.new(deps: Deps)
	local config = deps.config
	local records = deps.records
	local jobId = deps.jobId
	local sessions: { [number]: Session } = {}
	local listeners: { (event: Event) -> () } = {}
	local hooks: { LoadHook } = {}
	local closing = false
	local core = {}

	local function emit(event: Event)
		for _, listener in listeners do
			local ok, err = pcall(listener, event)
			if not ok then
				deps.log("warn", `listener errored: {err}`)
			end
		end
	end

	local function setStatus(session: Session, status: Status, detail: string?)
		session.status = status
		emit({ kind = "Status", userId = session.userId, status = status, detail = detail })
	end

	local function remove(session: Session)
		if sessions[session.userId] == session then
			sessions[session.userId] = nil
		end
		setStatus(session, "Released")
	end

	local function runHook(hook: LoadHook, session: Session)
		local ok, err = pcall(hook, session.userId, session.data)
		if not ok then
			deps.log("warn", `load hook errored for {session.userId}: {err}`)
		end
	end

	-- Runs one UpdateAsync with retries. The Studio fault switch throws like a store outage.
	local function update(session: Session, purpose: "Load" | "Save", transform: (old: any) -> any): (boolean, any)
		return deps.retry.run(function()
			if deps.injectFault and deps.injectFault(purpose) then
				error(`injected {purpose} failure (Studio switch)`, 0)
			end
			deps.store:UpdateAsync(session.key, transform)
			return nil
		end)
	end

	-- Another server took the lock or the record vanished: this server must never write the
	-- profile again. The player is kicked so they rejoin wherever the data now lives.
	local function markLost(session: Session, reason: string)
		if session.status == "Lost" then
			return
		end
		setStatus(session, "Lost", reason)
		deps.log("warn", `session lost for {session.userId} ({reason}); no further saves`)
		deps.kick(session.userId, config.LockLostKickMessage)
	end

	-- One write at a time per profile, so a later save never runs with an older snapshot.
	local function exclusive(session: Session, fn: () -> (boolean, string?)): (boolean, string?)
		while session.saving do
			deps.wait(config.SaveQueuePoll)
		end
		session.saving = true
		local ok, result, reason = pcall(fn)
		session.saving = false
		if not ok then
			deps.log("warn", `save step for {session.userId} errored: {result}`)
			return false, "Error"
		end
		return result :: boolean, reason
	end

	-- Writes the in-memory profile and renews (or, with release, clears) the lock in one
	-- UpdateAsync. On "StoreError" every attempt threw and the state stays in memory.
	local function write(session: Session, reason: string, release: boolean): (boolean, string?)
		local snapshot = deepCopy(session.data)
		local result, seq = "", 0
		local ok, err = update(session, "Save", function(old)
			local record
			record, result, seq =
				records.write(old, jobId, deps.now(), session.saveSeq, session.highestSeq, snapshot, release)
			session.highestSeq = math.max(session.highestSeq, seq)
			return record
		end)
		if not ok then
			deps.log("warn", `{reason} save for {session.userId} failed, state kept in memory: {err}`)
			emit({ kind = "Save", userId = session.userId, ok = false, reason = reason, detail = tostring(err) })
			return false, "StoreError"
		end
		if result ~= "Written" then
			emit({ kind = "Save", userId = session.userId, ok = false, reason = reason, detail = result })
			markLost(session, result)
			return false, result
		end
		session.saveSeq = seq
		emit({ kind = "Save", userId = session.userId, ok = true, reason = reason, seq = seq })
		return true, nil
	end

	function core.subscribe(listener: (event: Event) -> ())
		table.insert(listeners, listener)
	end

	-- Hooks run after the lock is taken and before the status becomes Loaded (e.g. the trade
	-- reconcile of #49). A hook registered later also runs for profiles that are already loaded.
	function core.addLoadHook(hook: LoadHook)
		table.insert(hooks, hook)
		for _, session in sessions do
			if session.status == "Loaded" then
				runHook(hook, session)
			end
		end
	end

	-- Loads until it works, the player leaves (release) or the server closes. Store errors set
	-- Failed and are retried every LoadRetryInterval; a fresh lock elsewhere is waited out.
	-- A read that failed is never taken as "new player".
	function core.load(userId: number): Status?
		while sessions[userId] ~= nil do
			local existing = sessions[userId]
			if closing then
				return nil
			end
			if not existing.cancelled and not existing.pendingRelease then
				return existing.status -- already loading or loaded
			end
			if existing.pendingRelease and not existing.saving and existing.status == "Loaded" then
				-- Rejoined before a failed release went through: this server still holds the
				-- lock and the newest state, so keep using it.
				existing.pendingRelease, existing.cancelled = false, false
				setStatus(existing, "Loaded", "Resumed")
				return "Loaded"
			end
			deps.wait(config.SaveQueuePoll)
		end

		local session: Session = {
			userId = userId,
			key = config.ProfileKeyPrefix .. tostring(userId),
			status = "Loading",
			data = nil,
			saveSeq = 0,
			highestSeq = 0,
			saving = false,
			cancelled = false,
			pendingRelease = false,
		}
		sessions[userId] = session
		setStatus(session, "Loading")

		while session.data == nil do
			if session.cancelled or closing then
				remove(session)
				return "Released"
			end
			local kind: string, info: any = "", nil
			local ok, err = update(session, "Load", function(old)
				local record
				record, kind, info = records.acquire(old, jobId, deps.now(), config.LockTimeout, deps.schema)
				return record
			end)
			if ok and (kind == "New" or kind == "Acquired" or kind == "Stolen") then
				session.data, session.saveSeq, session.highestSeq = info.data, info.seq, info.seq
				if kind == "Stolen" then
					deps.log("warn", `took over the stale lock of {info.detail} for {userId}`)
				end
				deps.log("info", `loaded {userId} ({kind}) saveSeq={info.seq}`)
			elseif ok and kind == "Locked" then
				setStatus(session, "Loading", "WaitingForLock")
				deps.wait(config.LockRetryInterval)
			else
				local why = if ok then `{kind}: {info.detail}` else `StoreError: {err}`
				deps.log("warn", `load for {userId} failed ({why}); nothing written, retrying`)
				setStatus(session, "Failed", if ok then kind else "StoreError")
				deps.wait(config.LoadRetryInterval)
			end
		end

		for _, hook in hooks do
			runHook(hook, session)
		end
		if sessions[userId] ~= session then
			return session.status -- released while the hooks ran
		end
		setStatus(session, "Loaded")
		if session.cancelled or closing then
			core.release(userId, "Leave")
			return session.status
		end
		return "Loaded"
	end

	-- Immediate save (purchases, barriers, rebirths, trades) and autosave. Returns only after the
	-- write is stored, so a caller that grants on true never loses the grant to a crash.
	function core.save(userId: number, reason: string): (boolean, string?)
		local session = sessions[userId]
		if session == nil then
			return false, "NoSession"
		end
		return exclusive(session, function()
			local writable = session.data ~= nil
				and (session.status == "Loaded" or session.status == "Loading")
				and not session.pendingRelease
			if not writable then
				return false, `not writable ({session.status})`
			end
			return write(session, reason, false)
		end)
	end

	-- Saves and gives up the lock (leave, BindToClose). If the save fails, the session keeps the
	-- lock and autosaveAll retries, so nothing is dropped and no other server can load an older
	-- state meanwhile.
	function core.release(userId: number, reason: string): (boolean, string?)
		local session = sessions[userId]
		if session == nil then
			return true, nil
		end
		session.cancelled = true
		if session.data == nil then
			return true, nil -- still loading; the load loop stops and cleans up
		end
		return exclusive(session, function()
			if sessions[userId] ~= session then
				return true, nil
			end
			if session.status == "Lost" or session.status == "Teleported" then
				remove(session)
				return true, nil
			end
			local ok, why = write(session, reason, true)
			if not ok and why == "StoreError" then
				session.pendingRelease = true
				return false, why
			end
			remove(session)
			return ok, why
		end)
	end

	-- Before a teleport: save and release. On false the lock is still held and the player
	-- should stay (concept 6.5). On true no further saves happen on this server.
	function core.prepareTeleport(userId: number): (boolean, string?)
		local session = sessions[userId]
		if session == nil then
			return false, "NotLoaded"
		end
		return exclusive(session, function()
			if session.status ~= "Loaded" or session.pendingRelease then
				return false, "NotLoaded"
			end
			local ok, why = write(session, "Teleport", true)
			if ok then
				setStatus(session, "Teleported")
			end
			return ok, why
		end)
	end

	-- The teleport failed after prepareTeleport: take the lock back, but only if nobody wrote
	-- the profile in between. Otherwise the session is lost and the player is kicked.
	function core.resumeAfterTeleport(userId: number): (boolean, string?)
		local session = sessions[userId]
		if session == nil then
			return false, "NotTeleported"
		end
		return exclusive(session, function()
			if session.status ~= "Teleported" then
				return false, "NotTeleported"
			end
			local result = ""
			local ok, err = update(session, "Load", function(old)
				local record
				record, result = records.resume(old, jobId, deps.now(), config.LockTimeout, session.saveSeq)
				return record
			end)
			if not ok then
				return false, `StoreError: {err}`
			end
			if result ~= "Resumed" then
				markLost(session, result)
				return false, result
			end
			setStatus(session, "Loaded", "Resumed")
			return true, nil
		end)
	end

	-- Every AutosaveInterval: renews each lock and retries releases that failed.
	function core.autosaveAll(): (number, number)
		local saved, failed = 0, 0
		for _, userId in core.userIds() do
			local session = sessions[userId]
			local ok
			if session == nil then
				continue
			elseif session.pendingRelease then
				ok = core.release(userId, "RetryRelease")
			elseif session.status == "Loaded" then
				ok = core.save(userId, "Autosave")
			else
				continue
			end
			if ok then
				saved += 1
			else
				failed += 1
			end
		end
		return saved, failed
	end

	-- BindToClose: no new loads from here on.
	function core.close()
		closing = true
	end

	function core.userIds(): { number }
		local ids = {}
		for userId in sessions do
			table.insert(ids, userId)
		end
		table.sort(ids)
		return ids
	end

	function core.getStatus(userId: number): Status?
		local session = sessions[userId]
		return if session then session.status else nil
	end

	-- The live profile table; owning services change it in place. Nil unless Loaded.
	function core.getData(userId: number): any
		local session = sessions[userId]
		if session and session.status == "Loaded" and not session.pendingRelease then
			return session.data
		end
		return nil
	end

	function core.getSaveSeq(userId: number): number?
		local session = sessions[userId]
		return if session then session.saveSeq else nil
	end

	-- Right-to-erasure (concept 12.1). Refuses while the player has a session on this server.
	-- A server elsewhere that still holds the player finds the record missing on its next save
	-- and stops (Lost) instead of writing it back.
	function core.eraseUser(userId: number): (boolean, string?)
		if type(userId) ~= "number" or userId < 1 or userId % 1 ~= 0 then
			return false, "userId must be a positive whole number"
		end
		if sessions[userId] ~= nil then
			return false, "the player has a session on this server; erase after they leave"
		end
		local ok, err = deps.retry.run(function()
			deps.store:RemoveAsync(config.ProfileKeyPrefix .. tostring(userId))
			return nil
		end)
		if not ok then
			return false, `profile: {tostring(err)}`
		end
		if deps.boards then
			return deps.boards.removeUser(userId)
		end
		return true, nil
	end

	return core
end

return table.freeze(DataCore)

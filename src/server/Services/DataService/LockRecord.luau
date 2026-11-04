--!strict
-- The UpdateAsync transforms behind the session lock and saveSeq rules (ADR 0003 rev 2).
-- Each takes the stored record and returns the record to write, or nil to cancel without
-- changing anything, plus an outcome. Pure and side-effect free, because Roblox may run a
-- transform more than once.
--
-- Stored record per player key: { saveSeq, lockServer?, lockTime?, data }.

export type AcquireKind = "New" | "Acquired" | "Stolen" | "Locked" | "Unusable"
export type WriteResult = "Written" | "Missing" | "LockLost" | "Stale"
export type ResumeResult = "Resumed" | "Missing" | "LockLost" | "Stale"

export type Schema = { newProfile: () -> any, prepare: (data: any) -> (any, string?) }

local LockRecord = {}

-- A lock held by another server that is younger than the timeout.
local function heldElsewhere(old: { [string]: any }, jobId: string, now: number, lockTimeout: number): boolean
	local holder = old.lockServer
	return holder ~= nil and holder ~= jobId and now - (tonumber(old.lockTime) or 0) < lockTimeout
end

-- Load: takes the lock if it is free, ours or stale. "Locked" and "Unusable" write nothing, so
-- a record this server cannot use is never replaced by defaults.
function LockRecord.acquire(
	old: any,
	jobId: string,
	now: number,
	lockTimeout: number,
	schema: Schema
): (any, AcquireKind, { detail: string?, data: any, seq: number })
	if old == nil then
		local data = schema.newProfile()
		return { saveSeq = 0, lockServer = jobId, lockTime = now, data = data }, "New", { data = data, seq = 0 }
	end
	if type(old) ~= "table" then
		return nil, "Unusable", { detail = "record is not a table", seq = 0 }
	end
	if heldElsewhere(old, jobId, now, lockTimeout) then
		local age = now - (tonumber(old.lockTime) or 0)
		return nil, "Locked", { detail = `held by {old.lockServer} for {age} s`, seq = 0 }
	end
	local data, reason = schema.prepare(old.data)
	if data == nil then
		return nil, "Unusable", { detail = reason, seq = 0 }
	end
	local seq = tonumber(old.saveSeq) or 0
	local holder = old.lockServer
	local kind: AcquireKind = if holder ~= nil and holder ~= jobId then "Stolen" else "Acquired"
	return { saveSeq = seq, lockServer = jobId, lockTime = now, data = data },
		kind,
		{ detail = holder, data = data, seq = seq }
end

-- Save: writes only while this server still holds the lock and the stored saveSeq is one this
-- server wrote (not above highestSeq). The new seq is one above both the stored and the last
-- known seq, so it grows even if an earlier attempt landed but reported an error.
-- With release the lock fields are left out, which frees the lock in the same write.
function LockRecord.write(
	old: any,
	jobId: string,
	now: number,
	saveSeq: number,
	highestSeq: number,
	snapshot: any,
	release: boolean
): (any, WriteResult, number)
	if type(old) ~= "table" then
		return nil, "Missing", 0
	end
	if old.lockServer ~= jobId then
		return nil, "LockLost", 0
	end
	local stored = tonumber(old.saveSeq) or 0
	if stored > highestSeq then
		return nil, "Stale", 0
	end
	local seq = math.max(stored, saveSeq) + 1
	if release then
		return { saveSeq = seq, data = snapshot }, "Written", seq
	end
	return { saveSeq = seq, lockServer = jobId, lockTime = now, data = snapshot }, "Written", seq
end

-- After a failed teleport: takes the lock back only if nobody else holds it and nobody wrote
-- since this server released it.
function LockRecord.resume(
	old: any,
	jobId: string,
	now: number,
	lockTimeout: number,
	expectedSeq: number
): (any, ResumeResult)
	if type(old) ~= "table" then
		return nil, "Missing"
	end
	if heldElsewhere(old, jobId, now, lockTimeout) then
		return nil, "LockLost"
	end
	if (tonumber(old.saveSeq) or 0) ~= expectedSeq then
		return nil, "Stale"
	end
	return { saveSeq = old.saveSeq, lockServer = jobId, lockTime = now, data = old.data }, "Resumed"
end

return table.freeze(LockRecord)

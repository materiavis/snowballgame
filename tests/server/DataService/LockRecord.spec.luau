--!strict
-- The UpdateAsync transforms on their own: lock freshness, steal, saveSeq and release.

local T = require("../../TestKit")
local H = require("./Harness")
local LockRecord = require("../../../src/server/Services/DataService/LockRecord")

local TIMEOUT = H.Config.LockTimeout
local NOW = 5000

local function stored(lockServer: string?, lockTime: number?, saveSeq: number): any
	return { saveSeq = saveSeq, lockServer = lockServer, lockTime = lockTime, data = H.Schema.newProfile() }
end

return T.suite("DataService/LockRecord", function(test)
	test("acquire: nothing stored means a new profile with our lock", function()
		local record, kind, info = LockRecord.acquire(nil, "A", NOW, TIMEOUT, H.Schema)
		T.equal(kind, "New")
		T.equal(record.lockServer, "A")
		T.equal(record.lockTime, NOW)
		T.equal(record.saveSeq, 0)
		T.equal(info.data, record.data)
	end)

	test("acquire: free, own and stale locks are taken; a fresh foreign lock is not", function()
		local _, free = LockRecord.acquire(stored(nil, nil, 3), "A", NOW, TIMEOUT, H.Schema)
		T.equal(free, "Acquired")
		local _, own = LockRecord.acquire(stored("A", NOW, 3), "A", NOW, TIMEOUT, H.Schema)
		T.equal(own, "Acquired")
		local fresh, locked = LockRecord.acquire(stored("B", NOW - TIMEOUT + 1, 3), "A", NOW, TIMEOUT, H.Schema)
		T.equal(fresh, nil, "cancelled, nothing written")
		T.equal(locked, "Locked")
		local record, stolen, info = LockRecord.acquire(stored("B", NOW - TIMEOUT, 3), "A", NOW, TIMEOUT, H.Schema)
		T.equal(stolen, "Stolen")
		T.equal(info.detail, "B")
		T.equal(record.lockServer, "A")
		T.equal(record.saveSeq, 3, "taking the lock does not bump saveSeq")
	end)

	test("acquire: unusable records are never replaced", function()
		local record, kind = LockRecord.acquire("garbage", "A", NOW, TIMEOUT, H.Schema)
		T.equal(record, nil)
		T.equal(kind, "Unusable")
		local newer, newerKind =
			LockRecord.acquire({ saveSeq = 1, data = { schemaVersion = 2 } }, "A", NOW, TIMEOUT, H.Schema)
		T.equal(newer, nil)
		T.equal(newerKind, "Unusable")
	end)

	test("write: renews the lock and bumps saveSeq; release clears the lock", function()
		local record, result, seq = LockRecord.write(stored("A", 1, 4), "A", NOW, 4, 4, { x = 1 }, false)
		T.equal(result, "Written")
		T.equal(seq, 5)
		T.equal(record.lockTime, NOW)
		T.equal(record.lockServer, "A")
		local released = LockRecord.write(stored("A", 1, 4), "A", NOW, 4, 4, { x = 1 }, true)
		T.equal(released.lockServer, nil)
		T.equal(released.lockTime, nil)
		T.equal(released.saveSeq, 5)
	end)

	test("write: refuses a foreign or missing lock, a missing record and a newer record", function()
		T.equal(select(2, LockRecord.write(stored("B", NOW, 4), "A", NOW, 4, 4, {}, false)), "LockLost")
		T.equal(select(2, LockRecord.write(stored(nil, nil, 4), "A", NOW, 4, 4, {}, false)), "LockLost")
		T.equal(select(2, LockRecord.write(nil, "A", NOW, 4, 4, {}, false)), "Missing")
		T.equal(select(2, LockRecord.write(stored("A", NOW, 9), "A", NOW, 4, 4, {}, false)), "Stale")
	end)

	test("write: an earlier attempt that landed but reported an error still gives a higher seq", function()
		-- We tried seq 5 (highestSeq 5), it was stored, but the call threw; saveSeq is still 4.
		local _, result, seq = LockRecord.write(stored("A", NOW, 5), "A", NOW, 4, 5, {}, false)
		T.equal(result, "Written")
		T.equal(seq, 6)
	end)

	test("resume: only if nobody else holds the lock and nobody wrote since", function()
		T.equal(select(2, LockRecord.resume(stored(nil, nil, 4), "A", NOW, TIMEOUT, 4)), "Resumed")
		T.equal(select(2, LockRecord.resume(stored("B", NOW, 4), "A", NOW, TIMEOUT, 4)), "LockLost")
		T.equal(select(2, LockRecord.resume(stored(nil, nil, 5), "A", NOW, TIMEOUT, 4)), "Stale")
		T.equal(select(2, LockRecord.resume(nil, "A", NOW, TIMEOUT, 4)), "Missing")
	end)
end)

--!strict
-- DataService-owned access to the stores outside player profiles (ADR 0003):
--   * TradeLedger: one entry per trade, read and written only through UpdateAsync, so the
--     trade service (#49) can do its "committed" / "aborted" check-and-set atomically.
--   * Global leaderboards (OrderedDataStores): values are queued and written on autosave
--     only, encoded so that coins up to Sx still fit an integer key.
-- The trade state machine and the leaderboard boards themselves belong to later issues.
-- Pure, no requires: stores, retry and config are injected.

local DATASTORE_KEY_MAX = 50 -- Roblox limit for DataStore key length
local MAX_EXACT_INTEGER = 2 ^ 53

export type Encoding = "Log" | "Raw"
export type Board = { Store: string, Encoding: Encoding }
export type Entry = { userId: number, value: number }

export type Deps = {
	ledger: any,
	-- OrderedDataStore per board id from config.Boards.
	ordered: { [string]: any },
	retry: { run: (fn: () -> any) -> (boolean, any) },
	log: (level: string, message: string) -> (),
	config: {
		LedgerKeyPrefix: string,
		LogScale: number,
		BoardPageSize: number,
		Boards: { [string]: Board },
	},
}

local GlobalStores = {}

function GlobalStores.encode(encoding: Encoding, value: number, logScale: number): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if encoding == "Log" then
		-- Values below 1 (including 0) share the lowest rank; leaderboards only rank positives.
		return math.floor(math.log10(math.max(value, 1)) * logScale)
	end
	local whole = math.floor(math.max(value, 0))
	if whole >= MAX_EXACT_INTEGER then
		return nil
	end
	return whole
end

function GlobalStores.decode(encoding: Encoding, stored: number, logScale: number): number
	if encoding == "Log" then
		return 10 ^ (stored / logScale)
	end
	return stored
end

-- Negative ids are Studio test players (Player1 = -1); live user ids are positive.
local function isUserId(value: any): boolean
	return type(value) == "number" and value ~= 0 and value % 1 == 0 and math.abs(value) < MAX_EXACT_INTEGER
end

function GlobalStores.new(deps: Deps)
	local config = deps.config
	local pending: { [string]: { [number]: number } } = {}
	local writesEnabled = true
	local self = {}

	local function ledgerKey(tradeId: any): string?
		if type(tradeId) ~= "string" or tradeId == "" then
			return nil
		end
		local key = config.LedgerKeyPrefix .. tradeId
		if #key > DATASTORE_KEY_MAX then
			return nil
		end
		return key
	end

	function self.getLedgerEntry(tradeId: string): (boolean, any)
		local key = ledgerKey(tradeId)
		if key == nil then
			return false, "invalid trade id"
		end
		return deps.retry.run(function()
			return deps.ledger:GetAsync(key)
		end)
	end

	-- transform(old) returns the new entry, or nil to leave the entry unchanged. It may run
	-- more than once (Roblox retries UpdateAsync on conflicts), so it must not have side effects.
	-- Returns true and the stored entry (nil if the transform cancelled), or false and the error.
	function self.updateLedgerEntry(tradeId: string, transform: (old: any) -> any): (boolean, any)
		local key = ledgerKey(tradeId)
		if key == nil then
			return false, "invalid trade id"
		end
		return deps.retry.run(function()
			return deps.ledger:UpdateAsync(key, function(old)
				return transform(old)
			end)
		end)
	end

	-- Private servers and similar callers switch writes off (concept 7.2); which servers that
	-- are is decided by the leaderboard feature.
	function self.setWritesEnabled(enabled: boolean)
		writesEnabled = enabled
		if not enabled then
			table.clear(pending)
		end
	end

	-- Remembers the newest value per player; flushBoards writes it on the next autosave.
	function self.queueBoardValue(boardId: string, userId: number, value: number): boolean
		local board = config.Boards[boardId]
		if not writesEnabled or board == nil or not isUserId(userId) then
			return false
		end
		if GlobalStores.encode(board.Encoding, value, config.LogScale) == nil then
			return false
		end
		pending[boardId] = pending[boardId] or {}
		pending[boardId][userId] = value
		return true
	end

	-- Values that fail to write stay queued for the next flush unless a newer value replaces them.
	function self.flushBoards(): (number, number)
		local written, failed = 0, 0
		for boardId, values in pending do
			local board = config.Boards[boardId]
			local store = deps.ordered[boardId]
			for userId, value in values do
				local encoded = GlobalStores.encode(board.Encoding, value, config.LogScale)
				local ok, err = deps.retry.run(function()
					store:SetAsync(tostring(userId), encoded)
					return nil
				end)
				if ok then
					values[userId] = nil
					written += 1
				else
					failed += 1
					deps.log("warn", `leaderboard {boardId} write for {userId} failed: {err}`)
				end
			end
		end
		return written, failed
	end

	function self.getTop(boardId: string, count: number): (boolean, any)
		local board = config.Boards[boardId]
		if board == nil then
			return false, "unknown board"
		end
		local pageSize = math.clamp(math.floor(count), 1, config.BoardPageSize)
		local ok, page = deps.retry.run(function()
			return deps.ordered[boardId]:GetSortedAsync(false, pageSize):GetCurrentPage()
		end)
		if not ok then
			return false, page
		end
		local entries: { Entry } = {}
		for _, item in page do
			local userId = tonumber(item.key)
			if userId then
				table.insert(entries, {
					userId = userId,
					value = GlobalStores.decode(board.Encoding, item.value, config.LogScale),
				})
			end
		end
		return true, entries
	end

	-- Right-to-erasure: removes the player from every board and drops queued values.
	function self.removeUser(userId: number): (boolean, string?)
		for _, values in pending do
			values[userId] = nil
		end
		for boardId in config.Boards do
			local ok, err = deps.retry.run(function()
				deps.ordered[boardId]:RemoveAsync(tostring(userId))
				return nil
			end)
			if not ok then
				return false, `board {boardId}: {tostring(err)}`
			end
		end
		return true, nil
	end

	return self
end

return table.freeze(GlobalStores)

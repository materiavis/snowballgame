--!strict
-- Persistence settings for DataService (ADR 0003 "Data model and failure behaviour", ADR 0006).
-- Times are in seconds. Store and key names are part of the save format: renaming one starts
-- every player from defaults, so they only change together with a migration plan.

local Data = {
	-- Concept 12.1: autosave every 2 minutes. Also the most progress a server crash can lose.
	AutosaveInterval = 120,

	-- A lock older than this counts as stale and may be stolen. Well above AutosaveInterval
	-- (at least 3 missed autosaves, ADR 0003), so one slow save never costs a live server its lock.
	LockTimeout = 600,
	-- How often a server retries while another server holds a fresh lock. Not below 6 s,
	-- the DataStore write limit per key.
	LockRetryInterval = 6,
	-- After a whole load attempt failed (store errors), wait this long and try again, for as
	-- long as the player stays (concept 6.5: portals stay locked until loading works).
	LoadRetryInterval = 30,

	-- Store calls that throw are retried with exponential backoff:
	-- BackoffBase, BackoffBase * BackoffFactor, ... capped at BackoffMax, StoreAttempts calls in total.
	StoreAttempts = 5,
	BackoffBase = 1,
	BackoffFactor = 2,
	BackoffMax = 8,

	-- How often a save waits for a save of the same profile that is still running.
	SaveQueuePoll = 0.1,
	-- BindToClose gives a server 30 s; leave a margin for the engine.
	BindToCloseTimeout = 25,

	-- Schema v1 defaults and bounds (ADR 0003 data model table).
	InventorySize = 50,
	TradeHistorySize = 50,
	ReceiptsKept = 100,

	-- Store names and key prefixes (see the note at the top).
	ProfileStoreName = "PlayerData",
	ProfileKeyPrefix = "user_",
	LedgerStoreName = "TradeLedger",
	LedgerKeyPrefix = "trade_",

	-- Global leaderboards (ADR 0003): "Log" stores floor(log10(v) * LogScale) for values that
	-- outgrow an integer (coins reach Sx = 1e21), "Raw" stores the whole number.
	-- Keys are board ids for DataService.QueueLeaderboardValue; Store is the OrderedDataStore name.
	LogScale = 1e6,
	Boards = table.freeze({
		TotalCoins = table.freeze({ Store = "Board_TotalCoins", Encoding = "Log" }),
		HighestZone = table.freeze({ Store = "Board_HighestZone", Encoding = "Raw" }),
		Rebirths = table.freeze({ Store = "Board_Rebirths", Encoding = "Raw" }),
		Wins = table.freeze({ Store = "Board_Wins", Encoding = "Raw" }),
		Freezes = table.freeze({ Store = "Board_Freezes", Encoding = "Raw" }),
		Level = table.freeze({ Store = "Board_Level", Encoding = "Raw" }),
	}),
	-- Most entries one leaderboard read returns (one OrderedDataStore page holds up to 100).
	BoardPageSize = 100,

	-- Shown when this server lost the session lock to another server.
	LockLostKickMessage = "Your progress was opened on another server. Please rejoin.",
}

return table.freeze(Data)

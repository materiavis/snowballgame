--!strict
-- Structural checks on Config.Data: the relations ADR 0003 requires between the numbers, not
-- the numbers themselves (except the 2-minute autosave the concept fixes).

local T = require("../TestKit")
local Data = require("../../src/shared/Config/Data")

local function positive(value: any): boolean
	return type(value) == "number" and value > 0 and value == value and value ~= math.huge
end

return T.suite("src/shared/Config/Data", function(test)
	test("is frozen and every tuning number is positive", function()
		T.isTrue(table.isfrozen(Data))
		for _, key in
			{
				"AutosaveInterval",
				"LockTimeout",
				"LockRetryInterval",
				"LoadRetryInterval",
				"StoreAttempts",
				"BackoffBase",
				"BackoffFactor",
				"BackoffMax",
				"SaveQueuePoll",
				"BindToCloseTimeout",
				"InventorySize",
				"TradeHistorySize",
				"ReceiptsKept",
				"LogScale",
				"BoardPageSize",
			}
		do
			T.isTrue(positive(Data[key]), key)
		end
	end)

	test("autosave every 2 minutes, lock timeout at least 3 missed autosaves", function()
		T.equal(Data.AutosaveInterval, 120, "concept 12.1")
		T.isTrue(Data.LockTimeout >= 3 * Data.AutosaveInterval, "ADR 0003: well above the autosave")
		T.isTrue(Data.LockRetryInterval >= 6, "DataStore write limit per key")
		T.isTrue(Data.BindToCloseTimeout < 30, "inside Roblox's 30 s shutdown window")
		T.isTrue(Data.BoardPageSize <= 100, "one OrderedDataStore page")
	end)

	test("every board names a store and a known encoding", function()
		for boardId, board in Data.Boards do
			T.equal(type(board.Store), "string", boardId)
			T.isTrue(board.Encoding == "Log" or board.Encoding == "Raw", boardId)
		end
	end)
end)

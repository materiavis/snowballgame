--!strict
-- Builds simulated servers (DataCore instances) that share one FakeStore, with a FakeClock,
-- an injected JobId, recorded kicks and logs. `wait` advances the clock and then calls the
-- optional onWait hook, which is how a test interleaves a second server or clears a fault
-- while the first one is waiting. Not a spec: the runner only loads *.spec.luau.

local FakeClock = require("../../helpers/FakeClock")
local DataConfig = require("../../../src/shared/Config/Data")
local DataCore = require("../../../src/server/Services/DataService/DataCore")
local FakeStore = require("../../../src/server/Services/DataService/FakeStore")
local GlobalStores = require("../../../src/server/Services/DataService/GlobalStores")
local LockRecord = require("../../../src/server/Services/DataService/LockRecord")
local Retry = require("../../../src/server/Services/DataService/Retry")
local Schema = require("../../../src/server/Services/DataService/Schema")

export type World = {
	clock: FakeClock.FakeClock,
	service: any, -- FakeStore.newService()
	store: any, -- the profile store
}

export type Server = {
	core: any,
	boards: any,
	jobId: string,
	kicks: { { userId: number, message: string } },
	logs: { string },
	events: { any },
	waits: { number },
	-- Called after every wait with the seconds waited. Assign in a test to interleave.
	onWait: ((seconds: number) -> ())?,
}

local Harness = {}

Harness.Config = DataConfig
Harness.Schema = Schema.new(DataConfig)
Harness.USER = 1001

function Harness.world(): World
	local service = FakeStore.newService()
	return {
		clock = FakeClock.new(1_000_000),
		service = service,
		store = service:GetDataStore(DataConfig.ProfileStoreName),
	}
end

-- injectFault is DataCore's Studio fault switch (DataFailLoad / DataFailSave in Studio), so a
-- test can force exactly the failure the playtester forces.
function Harness.server(world: World, jobId: string, injectFault: ((purpose: "Load" | "Save") -> boolean)?): Server
	local server: Server = {
		core = nil,
		boards = nil,
		jobId = jobId,
		kicks = {},
		logs = {},
		events = {},
		waits = {},
		onWait = nil,
	}
	local function wait(seconds: number)
		table.insert(server.waits, seconds)
		world.clock.advance(seconds)
		local hook = server.onWait
		if hook then
			hook(seconds)
		end
	end
	local function log(level: string, message: string)
		table.insert(server.logs, `{level}: {message}`)
	end
	local retry = Retry.new(DataConfig, wait)
	local ordered = {}
	for boardId, board in DataConfig.Boards do
		ordered[boardId] = world.service:GetOrderedDataStore(board.Store)
	end
	server.boards = GlobalStores.new({
		ledger = world.service:GetDataStore(DataConfig.LedgerStoreName),
		ordered = ordered,
		retry = retry,
		log = log,
		config = DataConfig,
	})
	server.core = DataCore.new({
		store = world.store,
		records = LockRecord,
		jobId = jobId,
		now = world.clock.now,
		wait = wait,
		retry = retry,
		schema = Harness.Schema,
		kick = function(userId: number, message: string)
			table.insert(server.kicks, { userId = userId, message = message })
		end,
		log = log,
		injectFault = injectFault,
		boards = server.boards,
		config = DataConfig,
	})
	server.core.subscribe(function(event)
		table.insert(server.events, event)
	end)
	return server
end

function Harness.key(userId: number): string
	return DataConfig.ProfileKeyPrefix .. tostring(userId)
end

function Harness.stored(world: World, userId: number): any
	return world.store:peek(Harness.key(userId))
end

function Harness.logged(server: Server, pattern: string): boolean
	for _, line in server.logs do
		if string.find(line, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Statuses this server reported for one user, in order.
function Harness.statuses(server: Server, userId: number): { string }
	local out = {}
	for _, event in server.events do
		if event.kind == "Status" and event.userId == userId then
			table.insert(out, event.status)
		end
	end
	return out
end

return table.freeze(Harness)

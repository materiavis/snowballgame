--!strict
-- DataService: the only module that touches DataStoreService (CLAUDE.md §6, ADR 0003, ADR 0006).
-- Owns player profiles (schema v1, session lock, autosave, immediate saves, teleport hand-off,
-- BindToClose), the trade ledger, the global leaderboard stores and right-to-erasure.
-- The logic lives in the pure child modules; this file only wires Roblox to them.
--
-- At game.PlaceId == 0 every store is the in-memory FakeStore and DataStoreService is never
-- even fetched. Every server writes the player attribute DataLoadStatus (the HUD reads it,
-- ADR 0008). In Studio the other load and save diagnostics are mirrored too, and the fake store
-- has fault switches on ServerScriptService (see ADR 0006). Live servers skip both.
--
-- Setup runs on the first Start() or API call, like NetService, because services start in
-- no fixed order and others call WhenProfileLoaded early.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Data"))
local DataCore = require(script:WaitForChild("DataCore"))
local FakeStore = require(script:WaitForChild("FakeStore"))
local GlobalStores = require(script:WaitForChild("GlobalStores"))
local LockRecord = require(script:WaitForChild("LockRecord"))
local Retry = require(script:WaitForChild("Retry"))
local Schema = require(script:WaitForChild("Schema"))
local StatusAttributes = require(script:WaitForChild("StatusAttributes"))
local StoreProvider = require(script:WaitForChild("StoreProvider"))

-- Studio-only switches and mirrors (ADR 0006). Attribute names are the playtest contract.
local FAIL_LOAD_ATTRIBUTE = "DataFailLoad"
local FAIL_SAVE_ATTRIBUTE = "DataFailSave"
local AUTOSAVE_NOW_ATTRIBUTE = "DataAutosaveNow"
local SIMULATE_REJOIN_ATTRIBUTE = "DataSimulateRejoin"

export type LoadStatus = "Loading" | "Loaded" | "Failed" | "Lost" | "Teleported" | "Released"

-- Mirror DataCore and StoreProvider. The requires above go through WaitForChild, so their
-- exported types are not visible here.
type StoreMode = "Fake" | "Real"
type Event = {
	kind: "Status" | "Save",
	userId: number,
	status: LoadStatus?,
	detail: string?,
	ok: boolean?,
	reason: string?,
	seq: number?,
}

local DataService = {}

local isStudio = RunService:IsStudio()
local statusChanged = Instance.new("BindableEvent")

-- Fires (player, status) whenever a player's load status changes. IsPortalLocked follows it.
DataService.LoadStatusChanged = statusChanged.Event

local core: any = nil
local globals: any = nil
local storeMode: StoreMode = "Fake"
local started = false

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[DataService] {message}`)
	elseif isStudio then
		print(`[DataService] {message}`)
	end
end

local function studioFault(purpose: "Load" | "Save"): boolean
	local name = if purpose == "Load" then FAIL_LOAD_ATTRIBUTE else FAIL_SAVE_ATTRIBUTE
	return ServerScriptService:GetAttribute(name) == true
end

-- Builds the stores and the core without connecting any player events, so the owner-run
-- EraseUserCommand can use it from the command bar.
local function ensureCore()
	if core then
		return
	end
	local provider, mode = StoreProvider.select(game.PlaceId, function()
		return game:GetService("DataStoreService")
	end, FakeStore.newService)
	storeMode = mode

	local retry = Retry.new(DataConfig, function(seconds)
		task.wait(seconds)
	end)
	local ordered = {}
	for boardId, board in DataConfig.Boards do
		ordered[boardId] = provider:GetOrderedDataStore(board.Store)
	end
	globals = GlobalStores.new({
		ledger = provider:GetDataStore(DataConfig.LedgerStoreName),
		ordered = ordered,
		retry = retry,
		log = log,
		config = DataConfig,
	})

	core = DataCore.new({
		store = provider:GetDataStore(DataConfig.ProfileStoreName),
		records = LockRecord,
		jobId = if game.JobId ~= "" then game.JobId else "Studio",
		now = os.time,
		wait = function(seconds)
			task.wait(seconds)
		end,
		retry = retry,
		schema = Schema.new(DataConfig),
		kick = function(userId, message)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				player:Kick(message)
			end
		end,
		log = log,
		-- Fault switches exist only for the fake store in Studio, never on a live server.
		injectFault = if mode == "Fake" and isStudio then studioFault else nil,
		boards = globals,
		config = DataConfig,
	})
end

-- Studio only: one console line per status change and save, next to the diagnostic attributes.
local function printEvent(event: Event)
	local player = Players:GetPlayerByUserId(event.userId)
	local name = if player then player.Name else "?"
	if event.kind == "Status" then
		print(`[DataService] {name} ({event.userId}) status={event.status} {event.detail or ""}`)
	else
		local outcome = if event.ok then `ok seq={event.seq}` else `failed: {event.detail}`
		print(`[DataService] {name} ({event.userId}) save {event.reason} {outcome}`)
	end
end

local function onPlayerAdded(player: Player)
	core.load(player.UserId)
end

local function onPlayerRemoving(player: Player)
	local ok, why = core.release(player.UserId, "Leave")
	if not ok then
		log("warn", `release of {player.UserId} on leave failed ({why}); autosave keeps retrying`)
	end
end

local function autosave(reason: string)
	local saved, failed = core.autosaveAll()
	local written = globals.flushBoards()
	log("info", `{reason}: {saved} saved, {failed} failed, {written} leaderboard values written`)
end

local function bindToClose()
	core.close()
	local remaining = 0
	for _, userId in core.userIds() do
		remaining += 1
		task.spawn(function()
			core.release(userId, "Shutdown")
			remaining -= 1
		end)
	end
	local deadline = os.clock() + DataConfig.BindToCloseTimeout
	while remaining > 0 and os.clock() < deadline do
		task.wait(DataConfig.SaveQueuePoll)
	end
	if remaining > 0 then
		warn(`[DataService] shutdown with {remaining} profiles not released (last autosave kept)`)
	end
end

local function setUp()
	if started then
		return
	end
	started = true
	ensureCore()

	core.subscribe(function(event: Event)
		if event.kind == "Status" then
			local player = Players:GetPlayerByUserId(event.userId)
			if player then
				statusChanged:Fire(player, event.status)
			end
		end
	end)

	-- Every server: DataLoadStatus. The diagnostics only in Studio.
	core.subscribe(StatusAttributes.listener({
		getPlayer = function(userId: number): any
			return Players:GetPlayerByUserId(userId)
		end,
		getSaveSeq = core.getSaveSeq,
		diagnostics = isStudio,
	}) :: any)

	if isStudio then
		core.subscribe(printEvent)
		ServerScriptService:SetAttribute("DataStoreMode", storeMode)
		if storeMode == "Fake" then
			for _, name in { FAIL_LOAD_ATTRIBUTE, FAIL_SAVE_ATTRIBUTE, AUTOSAVE_NOW_ATTRIBUTE } do
				if ServerScriptService:GetAttribute(name) == nil then
					ServerScriptService:SetAttribute(name, false)
				end
			end
			if ServerScriptService:GetAttribute(SIMULATE_REJOIN_ATTRIBUTE) == nil then
				ServerScriptService:SetAttribute(SIMULATE_REJOIN_ATTRIBUTE, 0)
			end
			ServerScriptService:GetAttributeChangedSignal(AUTOSAVE_NOW_ATTRIBUTE):Connect(function()
				if ServerScriptService:GetAttribute(AUTOSAVE_NOW_ATTRIBUTE) == true then
					ServerScriptService:SetAttribute(AUTOSAVE_NOW_ATTRIBUTE, false)
					task.spawn(autosave, "Studio autosave")
				end
			end)
			-- Leave + rejoin without disconnecting: release (save) then load again, so a playtest
			-- can exercise the load rules with DataFailLoad inside one Studio session.
			ServerScriptService:GetAttributeChangedSignal(SIMULATE_REJOIN_ATTRIBUTE):Connect(function()
				local userId = ServerScriptService:GetAttribute(SIMULATE_REJOIN_ATTRIBUTE)
				if type(userId) ~= "number" or userId == 0 then
					return
				end
				ServerScriptService:SetAttribute(SIMULATE_REJOIN_ATTRIBUTE, 0)
				if Players:GetPlayerByUserId(userId) == nil then
					warn(`[DataService] {SIMULATE_REJOIN_ATTRIBUTE}: no player with UserId {userId}`)
					return
				end
				task.spawn(function()
					local ok, why = core.release(userId, "StudioRejoin")
					if not ok then
						-- Like a real rejoin onto this server before the release went through:
						-- load resumes the in-memory session that still holds the lock.
						warn(`[DataService] {SIMULATE_REJOIN_ATTRIBUTE}: release failed ({why}); resuming`)
					end
					core.load(userId)
				end)
			end)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	game:BindToClose(bindToClose)

	task.spawn(function()
		while true do
			task.wait(DataConfig.AutosaveInterval)
			autosave("Autosave")
		end
	end)

	print(
		`[DataService] store={storeMode} (PlaceId {game.PlaceId}) autosave={DataConfig.AutosaveInterval}s lockTimeout={DataConfig.LockTimeout}s`
	)
end

function DataService.Start()
	setUp()
end

-- Yields until the player's profile is loaded and returns the live profile table, or nil if
-- the player left or the session ended first. Works whenever it is called.
function DataService.WhenProfileLoaded(player: Player): any
	setUp()
	while true do
		local status = core.getStatus(player.UserId)
		if status == "Loaded" then
			return core.getData(player.UserId)
		end
		if player.Parent ~= Players or status == "Lost" or status == "Released" or status == "Teleported" then
			return nil
		end
		statusChanged.Event:Wait()
	end
end

-- The live profile table, or nil if it is not loaded. Owning services change it in place.
function DataService.GetProfile(player: Player): any
	setUp()
	return core.getData(player.UserId)
end

-- Concept 6.5 load status for #35 (hint) and #37 (portal lock). Nil before the first load.
function DataService.GetLoadStatus(player: Player): LoadStatus?
	setUp()
	return core.getStatus(player.UserId)
end

-- Portals stay locked until the profile is loaded (concept 6.5).
function DataService.IsPortalLocked(player: Player): boolean
	setUp()
	return core.getStatus(player.UserId) ~= "Loaded"
end

-- Immediate save for Robux purchases, paid barriers, rebirths and completed trades. Yields and
-- returns true only once the profile is stored; on false the state stays on the server.
function DataService.SaveNow(player: Player, reason: string): (boolean, string?)
	setUp()
	return core.save(player.UserId, reason)
end

-- For TravelService (#28): save and release the lock before teleporting. On false keep the
-- player here and show a message (concept 6.5).
function DataService.PrepareTeleport(player: Player): (boolean, string?)
	setUp()
	return core.prepareTeleport(player.UserId)
end

-- For TravelService (#28): the teleport failed after PrepareTeleport; take the lock back.
function DataService.ResumeAfterTeleportFailure(player: Player): (boolean, string?)
	setUp()
	return core.resumeAfterTeleport(player.UserId)
end

-- Runs hook(userId, profile) after each load, before the status becomes Loaded; for the trade
-- reconcile of #49. Until something registers, loading has no extra step.
function DataService.RegisterLoadHook(hook: (userId: number, profile: any) -> ())
	setUp()
	core.addLoadHook(hook)
end

function DataService.GetLedgerEntry(tradeId: string): (boolean, any)
	ensureCore()
	return globals.getLedgerEntry(tradeId)
end

function DataService.UpdateLedgerEntry(tradeId: string, transform: (old: any) -> any): (boolean, any)
	ensureCore()
	return globals.updateLedgerEntry(tradeId, transform)
end

-- Queued and written on the next autosave (ADR 0003: at most once per autosave).
function DataService.QueueLeaderboardValue(boardId: string, userId: number, value: number): boolean
	ensureCore()
	return globals.queueBoardValue(boardId, userId, value)
end

function DataService.GetLeaderboardTop(boardId: string, count: number): (boolean, any)
	ensureCore()
	return globals.getTop(boardId, count)
end

-- The leaderboard feature switches this off where scores must not count (concept 7.2).
function DataService.SetLeaderboardWritesEnabled(enabled: boolean)
	ensureCore()
	globals.setWritesEnabled(enabled)
end

-- Right-to-erasure. Owners run it through EraseUserCommand, never through a remote.
function DataService.EraseUser(userId: number): (boolean, string?)
	ensureCore()
	return core.eraseUser(userId)
end

function DataService.GetStoreMode(): StoreMode
	ensureCore()
	return storeMode
end

return DataService

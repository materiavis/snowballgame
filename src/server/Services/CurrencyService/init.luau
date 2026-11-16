--!strict
-- CurrencyService: the only path that changes Coins, total coins and Snow Coins (concept 8.1,
-- ADR 0003, ADR 0007). Server only. Balances live in the DataService profile; this service
-- never touches DataStores and never saves by itself. The rules are in the pure CurrencyCore.
--
-- Callers that need the change stored at once (barriers, rebirths, purchases) spend first and
-- then call DataService.SaveNow(player, reason); see ADR 0007 for the pattern.
--
-- Every server mirrors the balances to player attributes (`Coins`, `SnowCoins`), which the HUD
-- reads (ADR 0008). In Studio at PlaceId 0 the totals and the last change are mirrored too, and
-- server switches on ServerScriptService add, spend or reset (ADR 0007). Live servers skip those.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local CurrencyConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Currency"))
local BalanceAttributes = require(script:WaitForChild("BalanceAttributes"))
local CurrencyCore = require(script:WaitForChild("CurrencyCore"))
local DataService = require(script.Parent:WaitForChild("DataService"))

-- Studio-only names (the playtest contract, ADR 0007). Per currency id <C>: switches
-- CurrencyAdd<C>, CurrencySpend<C>, CurrencyReset<C>; player attribute Total<C>.
local TARGET_ATTRIBUTE = "CurrencyTargetUserId"
local LAST_CHANGE_ATTRIBUTE = "CurrencyLastChange"
local REFUSALS_ATTRIBUTE = "CurrencyRefusals"
local STUDIO_REASON = "StudioSwitch"

-- Mirrors CurrencyCore.Event (types of WaitForChild requires are not visible here).
type Event = {
	kind: "Earn" | "Spend" | "Reset" | "Refused",
	operation: "Add" | "Spend" | "Reset",
	userId: number,
	currency: string,
	amount: number,
	balance: number?,
	total: number?,
	reason: string,
	refusal: string?,
	clamped: number?,
}

local CurrencyService = {}

CurrencyService.COINS = "Coins"
CurrencyService.SNOW_COINS = "SnowCoins"

local isStudio = RunService:IsStudio()
local studioTools = isStudio and game.PlaceId == 0
local started = false

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[CurrencyService] {message}`)
	elseif isStudio then
		print(`[CurrencyService] {message}`)
	end
end

local core = CurrencyCore.new({
	config = CurrencyConfig :: any,
	getProfile = function(userId: number): any
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			return nil
		end
		return DataService.GetProfile(player)
	end,
	log = log,
})

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function userIdOf(player: Player): number
	assert(isPlayer(player), "CurrencyService: expected a Player")
	return player.UserId
end

local balances = BalanceAttributes.new({
	core = core,
	getPlayer = function(userId: number): any
		return Players:GetPlayerByUserId(userId)
	end,
	diagnostics = studioTools,
})

local function mirrorBalances(player: Player)
	balances.mirror(player, player.UserId)
end

local function describe(event: Event): string
	if event.kind == "Refused" then
		local balance = tostring(event.balance)
		return `{event.currency} {event.operation} {event.amount} {event.reason} refused: {event.refusal} (balance {balance})`
	end
	local change = if event.kind == "Earn"
		then `+{event.amount}`
		elseif event.kind == "Spend" then `-{event.amount}`
		else `reset (was {event.amount})`
	local total = if event.total ~= nil then ` total={event.total}` else ""
	return `{event.currency} {change} {event.reason} -> {event.balance}{total}`
end

local function onStudioEvent(event: Event)
	local player = Players:GetPlayerByUserId(event.userId)
	local text = describe(event)
	print(`[CurrencyService] {if player then player.Name else "?"} ({event.userId}) {text}`)
	if player == nil then
		return
	end
	player:SetAttribute(LAST_CHANGE_ATTRIBUTE, text)
	if event.kind == "Refused" then
		player:SetAttribute(REFUSALS_ATTRIBUTE, ((player:GetAttribute(REFUSALS_ATTRIBUTE) :: number?) or 0) + 1)
	end
end

-- Targets of a Studio switch: CurrencyTargetUserId, or every player when it is 0.
local function studioTargets(): { Player }
	local target = ServerScriptService:GetAttribute(TARGET_ATTRIBUTE)
	if type(target) == "number" and target ~= 0 then
		local player = Players:GetPlayerByUserId(target)
		if player == nil then
			warn(`[CurrencyService] {TARGET_ATTRIBUTE}: no player with UserId {target}`)
			return {}
		end
		return { player }
	end
	return Players:GetPlayers()
end

-- A number switch runs once per value and resets itself to 0 (0 itself does nothing). The value
-- goes through the normal checks, so NaN, -5, 1.5 or math.huge show a refusal.
local function bindAmountSwitch(name: string, action: (userId: number, amount: number) -> ())
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, 0)
	end
	ServerScriptService:GetAttributeChangedSignal(name):Connect(function()
		local amount = ServerScriptService:GetAttribute(name)
		if amount == 0 or amount == nil then
			return
		end
		ServerScriptService:SetAttribute(name, 0)
		for _, player in studioTargets() do
			action(player.UserId, amount :: any)
		end
	end)
end

local function bindResetSwitch(name: string, currency: string)
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, false)
	end
	ServerScriptService:GetAttributeChangedSignal(name):Connect(function()
		if ServerScriptService:GetAttribute(name) ~= true then
			return
		end
		ServerScriptService:SetAttribute(name, false)
		for _, player in studioTargets() do
			core.reset(player.UserId, currency, STUDIO_REASON)
		end
	end)
end

local function setUpStudio()
	core.subscribe(onStudioEvent)
	if ServerScriptService:GetAttribute(TARGET_ATTRIBUTE) == nil then
		ServerScriptService:SetAttribute(TARGET_ATTRIBUTE, 0)
	end
	for _, currency in core.currencies() do
		bindAmountSwitch(`CurrencyAdd{currency}`, function(userId, amount)
			core.add(userId, currency, amount, STUDIO_REASON)
		end)
		bindAmountSwitch(`CurrencySpend{currency}`, function(userId, amount)
			core.spend(userId, currency, amount, STUDIO_REASON)
		end)
		bindResetSwitch(`CurrencyReset{currency}`, currency)
	end
end

local function setUp()
	if started then
		return
	end
	started = true

	-- Every server: balances on load and after every change.
	core.subscribe(balances.onEvent)
	DataService.LoadStatusChanged:Connect(function(player: Player, status: string)
		if status == "Loaded" then
			mirrorBalances(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if DataService.GetProfile(player) ~= nil then
			mirrorBalances(player)
		end
	end

	if studioTools then
		setUpStudio()
	end
	print(`[CurrencyService] started currencies={table.concat(core.currencies(), ",")} studioSwitches={studioTools}`)
end

function CurrencyService.Start()
	setUp()
end

-- Generic API. `currency` is a Config.Currency id ("Coins", "SnowCoins"). `amount` must be a
-- finite whole number >= 0 and at most the currency's MaxChange. Returns true and the new
-- balance, or false and a refusal ("NotLoaded", "Insufficient", "BadAmount", ...). A refused
-- call changes nothing.

function CurrencyService.Add(player: Player, currency: string, amount: number, reason: string): (boolean, any)
	setUp()
	return core.add(userIdOf(player), currency, amount, reason)
end

function CurrencyService.Spend(player: Player, currency: string, amount: number, reason: string): (boolean, any)
	setUp()
	return core.spend(userIdOf(player), currency, amount, reason)
end

-- Balance to 0, total unchanged (rebirth, concept 7.10).
function CurrencyService.Reset(player: Player, currency: string, reason: string): (boolean, any)
	setUp()
	return core.reset(userIdOf(player), currency, reason)
end

-- Nil while the profile is not loaded.
function CurrencyService.Get(player: Player, currency: string): number?
	setUp()
	return core.get(userIdOf(player), currency)
end

function CurrencyService.GetTotal(player: Player, currency: string): number?
	setUp()
	return core.getTotal(userIdOf(player), currency)
end

function CurrencyService.CanAfford(player: Player, currency: string, amount: number): boolean
	setUp()
	return core.canAfford(userIdOf(player), currency, amount)
end

-- Every Earn, Spend, Reset and Refused event. The hook for AnalyticsService (#43) economy
-- events; returns a function that unsubscribes.
function CurrencyService.Subscribe(listener: (event: Event) -> ()): () -> ()
	return core.subscribe(listener :: any)
end

-- Shorthands for the two currencies of this game.

function CurrencyService.GetCoins(player: Player): number?
	return CurrencyService.Get(player, CurrencyService.COINS)
end

function CurrencyService.GetTotalCoins(player: Player): number?
	return CurrencyService.GetTotal(player, CurrencyService.COINS)
end

function CurrencyService.AddCoins(player: Player, amount: number, reason: string): (boolean, any)
	return CurrencyService.Add(player, CurrencyService.COINS, amount, reason)
end

function CurrencyService.SpendCoins(player: Player, amount: number, reason: string): (boolean, any)
	return CurrencyService.Spend(player, CurrencyService.COINS, amount, reason)
end

function CurrencyService.ResetCoins(player: Player, reason: string): (boolean, any)
	return CurrencyService.Reset(player, CurrencyService.COINS, reason)
end

function CurrencyService.GetSnowCoins(player: Player): number?
	return CurrencyService.Get(player, CurrencyService.SNOW_COINS)
end

function CurrencyService.AddSnowCoins(player: Player, amount: number, reason: string): (boolean, any)
	return CurrencyService.Add(player, CurrencyService.SNOW_COINS, amount, reason)
end

function CurrencyService.SpendSnowCoins(player: Player, amount: number, reason: string): (boolean, any)
	return CurrencyService.Spend(player, CurrencyService.SNOW_COINS, amount, reason)
end

return CurrencyService

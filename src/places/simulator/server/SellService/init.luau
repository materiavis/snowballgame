--!strict
-- SellService (Simulator only, concept 7.5, 8.3, ADR 0012): selling at the scale. Pushing the
-- ball onto a scale plate sells it automatically, also before the maximum. The rules are in the
-- pure SellCore; this file wires them to BallService, UpgradeService, CurrencyService, the map
-- and the client feedback.
--
-- No client asks for a sale. The server checks, every Config.Sell.CheckInterval, whether each
-- ball touches a bound ScalePlate (its own view of the client-owned ball) while its owner's
-- living character is at the ball (the 7.4 growth range). Coins go through CurrencyService
-- (reason Config.Sell.CoinReason); like every coin gain they land with the next autosave. Then
-- the ball shrinks to start size and the client gets the coins on the SaleResult remote.
--
-- In Studio at PlaceId 0, switches on ServerScriptService and diagnostics on the Player support
-- playtests (SellSwitches). Live servers skip all of it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local SellConfig = require(Config:WaitForChild("Sell")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local BallConfig = require(Config:WaitForChild("Ball")) :: any
local ZonesConfig = require(Config:WaitForChild("Zones")) :: any
local EconomyConfig = require(Config:WaitForChild("Economy")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))

local PlateGeometry = require(script:WaitForChild("PlateGeometry"))
local SaleOverride = require(script:WaitForChild("SaleOverride"))
local ScalePlates = require(script:WaitForChild("ScalePlates"))
local SellCore = require(script:WaitForChild("SellCore"))
local SellSwitches = require(script:WaitForChild("SellSwitches"))

local BallService = require(script.Parent:WaitForChild("BallService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local Services = script.Parent.Parent:WaitForChild("Services")
local CurrencyService = require(Services:WaitForChild("CurrencyService"))
local DataService = require(Services:WaitForChild("DataService"))
local NetService = require(Services:WaitForChild("NetService"))

local REMOTE = "SaleResult"
local SELL_VALUE = "sellValue"

type Flags = { [string]: boolean }

local SellService = {}

local isStudio = RunService:IsStudio()
local studioTools = isStudio and game.PlaceId == 0
local started = false
local flagNames = SaleOverride.flagNames(EconomyConfig)
-- ScalePlates.Plates, set in Start.
local plates: any = nil

local function log(level: "info" | "warn", message: string)
	if level == "warn" then
		warn(`[SellService] {message}`)
	elseif isStudio then
		print(`[SellService] {message}`)
	end
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- The sale bonuses that are active for a player (concept 8.3): Double coins (game pass), Coins
-- boost, Golden snow (event), VIP and Premium. None of their sources exists yet (game passes
-- and VIP 9.x, boosts, events 7.11), so every flag is off. Those features fill this function;
-- it is the only place the sale reads bonuses from.
local function activeBonusFlags(_player: Player): Flags
	return SaleOverride.noFlags(flagNames)
end

local core = SellCore.new({
	economy = Formulas.Economy,
	ballValue = Formulas.Zones.ballValue,
	config = SellConfig,
	getProfile = function(userId: number): any
		local player = playerOf(userId)
		return if player then DataService.GetProfile(player) else nil
	end,
	sizeMetres = function(userId: number): number?
		local player = playerOf(userId)
		return if player then BallService.GetSizeMetres(player) else nil
	end,
	resetBall = function(userId: number): boolean
		local player = playerOf(userId)
		return player ~= nil and BallService.ResetSize(player)
	end,
	-- Written by PetService (#41) on the server; a client-side write does not replicate.
	petMultiplier = function(userId: number): any
		local player = playerOf(userId)
		return if player then player:GetAttribute(SellConfig.PetMultiplierAttribute) else nil
	end,
	sellValueLevel = function(userId: number): number
		local player = playerOf(userId)
		return if player then UpgradeService.GetLevel(player, SELL_VALUE) else 0
	end,
	-- Read at every sale, so a Sell value purchase counts from the next sale on (AC5).
	sellMultiplier = function(userId: number): number
		local player = playerOf(userId)
		return if player then UpgradeService.GetEffect(player, SELL_VALUE) else 1
	end,
	bonusFlags = function(userId: number): Flags
		local player = playerOf(userId)
		return if player then activeBonusFlags(player) else SaleOverride.noFlags(flagNames)
	end,
	addCoins = function(userId: number, amount: number, reason: string): (boolean, any)
		local player = playerOf(userId)
		if player == nil then
			return false, SellCore.Refusal.NotLoaded
		end
		return CurrencyService.AddCoins(player, amount, reason)
	end,
	log = log,
})

local function round(value: number, digits: number): string
	return string.format(`%.{digits}f`, value)
end

local function describe(event: any): string
	local sale = event.sale
	local head = if event.kind == "Sale" then `sold coins={sale.coins}` else `refused: {event.refusal}`
	if sale == nil then
		return head
	end
	return table.concat({
		head,
		`zone={tostring(sale.zone)}`,
		`size={round(sale.sizeMetres, 4)}m`,
		`ballValue={round(sale.ballValue, 4)}`,
		`finds={sale.findsValue}`,
		`pets={sale.petMultiplier}`,
		`rebirths={sale.rebirths} (x{sale.rebirthMultiplier})`,
		`sellValue={sale.sellMultiplier} (level {sale.sellValueLevel})`,
		`bonus={sale.bonus}`,
		`flags={SaleOverride.describeFlags(sale.flags)}`,
		`quote={sale.coins}`,
		`balance={tostring(sale.balance)}`,
	}, " ")
end

-- Every server: the client shows "+3.4K" flying to the Coins display.
local function onEvent(event: any)
	if event.kind ~= "Sale" then
		return
	end
	local player = playerOf(event.userId)
	if player and player.Parent == Players then
		(NetService.getRemote(REMOTE) :: any):FireClient(player, event.sale.coins)
	end
end

-- Last written SellTouching / SellLatched per player (Studio diagnostics, written on change).
local touchingSent: { [Player]: boolean } = {}
local latchedSent: { [Player]: boolean } = {}

local function check(player: Player)
	local part = BallService.GetBallPart(player)
	if part == nil then
		return
	end
	local gap, zone = plates.nearest(part.Position, part.Size.X / 2)
	local touching, clear = PlateGeometry.classify(gap, SellConfig)
	core.step(player.UserId, {
		touching = touching,
		clear = clear,
		held = touching and BallService.IsHeld(player),
		zone = zone,
	})
	if studioTools then
		local names = SellConfig.DiagnosticAttributes
		local latched = core.isLatched(player.UserId)
		if touchingSent[player] ~= touching then
			touchingSent[player] = touching
			player:SetAttribute(names.Touching, touching)
		end
		if latchedSent[player] ~= latched then
			latchedSent[player] = latched
			player:SetAttribute(names.Latched, latched)
		end
	end
end

local function setUpStudio()
	local names = SellConfig.DiagnosticAttributes
	core.subscribe(function(event: any)
		local player = playerOf(event.userId)
		local text = describe(event)
		print(`[SellService] {if player then player.Name else "?"} ({event.userId}) {text}`)
		if player then
			SellSwitches.writeDiagnostics(player, names, event, describe)
			player:SetAttribute(names.FindsValue, core.findsValue(event.userId))
		end
	end)
	SellSwitches.bind(ServerScriptService, {
		setTestGeometry = function(zone: number, origin: CFrame?): string
			local exclude: { Instance } = {}
			local balls = Workspace:FindFirstChild(BallConfig.FolderName)
			if balls then
				table.insert(exclude, balls)
			end
			for _, other in Players:GetPlayers() do
				if other.Character then
					table.insert(exclude, other.Character)
				end
			end
			return plates.setTestGeometry(zone, origin, exclude)
		end,
		addFindValue = function(player: Player, value: any): (boolean, string?)
			local ok, refusal = SellService.AddFindValue(player, value)
			player:SetAttribute(names.FindsValue, core.findsValue(player.UserId))
			return ok, refusal
		end,
		findsValue = function(player: Player): number
			return core.findsValue(player.UserId)
		end,
		setOverride = function(text: any): string
			local override, problem = SaleOverride.parse(text, flagNames)
			core.setOverride(override)
			if problem then
				return `invalid ({problem}), no override`
			end
			return if override then `override {text}` else "no override"
		end,
	})
end

function SellService.Start()
	if started then
		return
	end
	started = true

	plates = ScalePlates.start({
		map = MapConfig,
		sell = SellConfig,
		scaleAnchorTag = BallConfig.ScaleAnchorTag,
		worldIndex = PlaceInfo.WorldIndex :: number,
		zoneCount = ZonesConfig.ZoneCount,
		isZone = Formulas.Zones.isZone,
		worldOf = Formulas.Zones.worldOf,
		log = function(message: string)
			log("info", message)
		end,
	})
	NetService.Start()
	core.subscribe(onEvent)
	if studioTools then
		setUpStudio()
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		-- 6.5: the finds in the ball are lost when the player leaves.
		core.forget(player.UserId)
		touchingSent[player] = nil
		latchedSent[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < SellConfig.CheckInterval then
			return
		end
		accumulator = 0
		for _, player in Players:GetPlayers() do
			check(player)
		end
	end)

	print(`[SellService] started plates={plates.count()} studioSwitches={studioTools}`)
end

-- For finds (#40): adds the value of a picked-up find (Formulas.Economy.findValue) to the
-- player's current ball. A sale pays it out and empties it; leaving loses it (6.5). Returns
-- false and "BadValue" (not a finite number >= 0) or "TooLarge".
function SellService.AddFindValue(player: Player, value: number): (boolean, string?)
	return core.addFindValue(player.UserId, value)
end

-- Finds value in the player's current ball.
function SellService.GetFindValue(player: Player): number
	return core.findsValue(player.UserId)
end

-- Every Sale and Refused event, for AnalyticsService (#43) and finds (#40). Returns an
-- unsubscribe. Listeners must not yield.
function SellService.Subscribe(listener: (event: any) -> ()): () -> ()
	return core.subscribe(listener)
end

return SellService

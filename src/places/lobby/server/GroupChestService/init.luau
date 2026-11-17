--!strict
-- GroupChestService: the Lobby group chest (concept 7.1, 6.5; ADR 0009, ADR 0015). Binds every
-- `GroupChest` station below Workspace.Map with a prompt from the #90 prompt component. On
-- trigger the server checks reach, rate and the claim itself (ChestCore), asks Roblox whether
-- the player is in the group Config.Economy.GroupId (pcall, cached), grants the Coins and
-- Snow Coins through CurrencyService and saves at once. The player sees a pop-up.
--
-- The reward's egg (Egg 1, #41) and hat (fight cosmetics, Launch) do not exist yet; the slice
-- grants the Coins and Snow Coins only (PR #37 "Decided by Dev Manager").
--
-- GroupId 0 is the placeholder: on a live server nobody is a member and the chest says it opens
-- soon. In Studio at PlaceId 0 the switch LobbyStudioGroup answers the membership instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EconomyConfig = require(Config:WaitForChild("Economy")) :: any
local LobbyConfig = require(Config:WaitForChild("Lobby")) :: any
local UiConfig = require(Config:WaitForChild("Ui")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes"))
local Prompts = require(Shared:WaitForChild("Prompts"))

local Services = script.Parent.Parent:WaitForChild("Services")
local CurrencyService = require(Services:WaitForChild("CurrencyService")) :: any
local DataService = require(Services:WaitForChild("DataService")) :: any
local PopupService = require(Services:WaitForChild("PopupService")) :: any

local LobbyMap = require(script.Parent:WaitForChild("LobbyMap"))
local ChestCore = require(script:WaitForChild("ChestCore"))

local MapConfig = LobbyMap.Config
local PromptSpec = require(Shared:WaitForChild("Prompts"):WaitForChild("PromptSpec")) :: any

-- Mirrors ChestCore.Membership (types of WaitForChild requires are not visible here).
type Membership = "Member" | "NotMember" | "NoGroup" | "Error"

local PROMPT_PRESET = "GroupChest"
local PROMPT_TAG = "GroupChestPrompt"
local GROUP_SWITCH = "LobbyStudioGroup"
local STUDIO_ANSWERS = { Member = true, NotMember = true, Error = true }
local REASON = "GroupChest"

-- Pop-up key per outcome. Busy and Cooldown show nothing: a double tap is one open (6.5).
local POPUPS: { [string]: string } = {
	AlreadyOpened = "GroupChestAlreadyOpened",
	NotMember = "GroupChestJoinGroup",
	NoGroup = "GroupChestNoGroup",
	TryLater = "GroupChestTryLater",
	NotReady = "GroupChestNotReady",
}

local GroupChestService = {}

local studioTools = RunService:IsStudio() and game.PlaceId == 0
local started = false

local function log(message: string)
	if RunService:IsStudio() then
		print(`[GroupChestService] {message}`)
	end
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- The real check: true, false, or nil when the web call failed. IsInGroupAsync is the current
-- API; IsInGroup is the fallback where it does not exist yet.
local function queryGroup(userId: number): boolean?
	local player = playerOf(userId)
	if player == nil then
		return nil
	end
	local groupId = EconomyConfig.GroupId
	local ok, member = pcall(function(): boolean
		local target = player :: any
		local asyncOk, result = pcall(function()
			return target:IsInGroupAsync(groupId)
		end)
		if asyncOk then
			return result == true
		end
		return target:IsInGroup(groupId) == true
	end)
	if not ok then
		warn(`[GroupChestService] group check for {userId} failed: {member}`)
		return nil
	end
	return member
end

local cache = LobbyMap.AnswerCache.new(queryGroup, LobbyConfig.GroupMembershipRecheck, os.clock)

local function membership(userId: number): Membership
	if studioTools then
		local answer = ServerScriptService:GetAttribute(GROUP_SWITCH)
		if type(answer) == "string" and STUDIO_ANSWERS[answer] then
			return answer :: any
		end
	end
	if type(EconomyConfig.GroupId) ~= "number" or EconomyConfig.GroupId <= 0 then
		return "NoGroup"
	end
	local member = cache.get(userId)
	if member == nil then
		return "Error"
	end
	return if member then "Member" else "NotMember"
end

local core = ChestCore.new({
	coins = EconomyConfig.GroupChestCoins,
	snowCoins = EconomyConfig.GroupChestSnowCoins,
	cooldown = LobbyConfig.GroupChestCooldown,
	reach = PromptSpec.resolve(PROMPT_PRESET, UiConfig).MaxActivationDistance + LobbyConfig.GroupChestReachSlack,
	now = os.clock,
	getProfile = function(userId: number): any
		local player = playerOf(userId)
		return if player then DataService.GetProfile(player) else nil
	end,
	membership = function(userId: number): Membership
		local answer = membership(userId)
		local player = playerOf(userId)
		if studioTools and player then
			player:SetAttribute(LobbyAttributes.GROUP_MEMBER, answer)
		end
		return answer
	end,
	addCoins = function(userId: number, amount: number): boolean
		local player = playerOf(userId)
		return player ~= nil and (CurrencyService.AddCoins(player, amount, REASON))
	end,
	addSnowCoins = function(userId: number, amount: number): boolean
		local player = playerOf(userId)
		return player ~= nil and (CurrencyService.AddSnowCoins(player, amount, REASON))
	end,
	granted = function(userId: number)
		local player = playerOf(userId)
		if player then
			PopupService.show(
				player,
				"GroupChestOpened",
				{ EconomyConfig.GroupChestCoins, EconomyConfig.GroupChestSnowCoins }
			)
		end
	end,
	save = function(userId: number): boolean
		local player = playerOf(userId)
		if player == nil then
			return false
		end
		local ok, why = DataService.SaveNow(player, REASON)
		if not ok then
			-- The claim and the balances stay on the server together and go out with the next
			-- autosave or the leave save (ADR 0007 pattern).
			warn(`[GroupChestService] save after the chest for {player.Name} failed ({why}); kept for the next save`)
		end
		return ok
	end,
	log = function(message: string)
		warn(`[GroupChestService] {message}`)
	end,
})

local function onTriggered(chest: Model, player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return
	end
	local root = LobbyMap.rootOf(player)
	local primary = chest.PrimaryPart
	local distance = if root and primary then (root.Position - primary.Position).Magnitude else math.huge
	local result = core.open(player.UserId, distance)
	local outcome = result.outcome
	-- "Opened" showed its pop-up at the grant (ChestCore deps.granted).
	if POPUPS[outcome] then
		PopupService.show(player, POPUPS[outcome])
	end
	local text = if result.saved == nil then outcome else `{outcome} saved={result.saved}`
	log(`{player.Name} ({player.UserId}) {text}`)
	if studioTools and player.Parent == Players then
		player:SetAttribute(LobbyAttributes.GROUP_CHEST_LAST, text)
	end
end

local function setUp()
	if started then
		return
	end
	started = true

	local prompts: { [Instance]: ProximityPrompt } = {}
	local chests = LobbyMap.bindTag(MapConfig.Tags.GroupChest, LobbyMap.rules.checkStation, function(instance)
		local model = instance :: Model
		local prompt = Prompts.create(PROMPT_PRESET, model.PrimaryPart :: BasePart, { tag = PROMPT_TAG })
		prompt.Triggered:Connect(function(player: Player)
			onTriggered(model, player)
		end)
		prompts[instance] = prompt
		log(`chest bound {instance:GetFullName()}`)
	end, function(instance)
		local prompt = prompts[instance]
		prompts[instance] = nil
		if prompt then
			prompt:Destroy()
		end
	end)
	LobbyMap.warnCount(MapConfig.Tags.GroupChest, #chests(), "some")

	Players.PlayerRemoving:Connect(function(player)
		core.forget(player.UserId)
		cache.forget(player.UserId)
	end)

	if studioTools and ServerScriptService:GetAttribute(GROUP_SWITCH) == nil then
		ServerScriptService:SetAttribute(GROUP_SWITCH, "")
	end
	print(
		`[GroupChestService] started chests={#chests()} groupId={EconomyConfig.GroupId} reward={EconomyConfig.GroupChestCoins}+{EconomyConfig.GroupChestSnowCoins} studioSwitches={studioTools}`
	)
end

function GroupChestService.Start()
	setUp()
end

-- Studio reset (LobbyStudioReset, ADR 0015): the chest can be opened again. Balances stay; use
-- CurrencyResetCoins / CurrencyResetSnowCoins (ADR 0007) to reset them.
function GroupChestService.StudioResetClaim(player: Player): boolean
	assert(studioTools, "GroupChestService.StudioResetClaim is Studio-only")
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	profile.groupChestClaimed = false
	core.forget(player.UserId)
	return true
end

return GroupChestService

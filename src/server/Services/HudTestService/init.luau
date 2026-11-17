--!strict
-- Studio-only playtest switches for the HUD scaffold (#90, ADR 0008 "Studio switches"). Bound
-- only in Studio at game.PlaceId == 0, and not in the Arena (its HUD is #91). Attributes on
-- ServerScriptService, which does not replicate, so each switch turns into something the
-- client sees (a pop-up through PopupService, a part with a prompt, a player attribute):
--   HudTargetUserId number, idle 0: player the switches act on; 0 = every player
--   HudTestPopup    string, idle "": "<TextKey>[,<n1>[,<n2>]]" shows that pop-up to the target;
--                   resets itself to ""
--   HudTestPrompt   bool: true builds the placeholder prompt near the first SpawnLocation,
--                   false removes it. Each trigger prints, counts HudTestPromptTriggers and
--                   shows the "PromptTriggered" pop-up to the player who used it
--   HudTestButtons  bool: mirrored to the target players' HudTestButtons attribute; the
--                   Simulator HUD then registers placeholder Pets, ZoneTeleport and Lobby buttons
-- Invalid values only warn. Live servers bind nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ui")) :: any
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))
local Prompts = require(Shared:WaitForChild("Prompts"))
local PopupService = require(script.Parent:WaitForChild("PopupService"))
local PopupSwitch = require(script:WaitForChild("PopupSwitch"))

local TARGET_SWITCH = "HudTargetUserId"
local POPUP_SWITCH = "HudTestPopup"
local PROMPT_SWITCH = "HudTestPrompt"
local BUTTONS_SWITCH = "HudTestButtons"
local TRIGGER_COUNT = "HudTestPromptTriggers"
local PROMPT_PART = "HudTestPromptPart"
local PROMPT_NAME = "HudTestPrompt"
local PROMPT_TEXT = "PromptTriggered"

local HudTestService = {}

local started = false

local function isTarget(player: Player): boolean
	local target = ServerScriptService:GetAttribute(TARGET_SWITCH)
	return type(target) ~= "number" or target == 0 or player.UserId == target
end

local function targets(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if isTarget(player) then
			table.insert(list, player)
		end
	end
	return list
end

local function ensure(name: string, default: any)
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, default)
	end
end

local function vector(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

-- The first SpawnLocation, else the first target's character: where the prompt goes.
local function promptOrigin(): CFrame?
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			return instance.CFrame
		end
	end
	for _, player in targets() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.CFrame
		end
	end
	return nil
end

local function removePrompt()
	local old = Workspace:FindFirstChild(PROMPT_PART)
	if old then
		old:Destroy()
	end
end

local function buildPrompt()
	removePrompt()
	local origin = promptOrigin()
	if origin == nil then
		warn(`[HudTestService] {PROMPT_SWITCH}: no SpawnLocation and no character to place the prompt at`)
		return
	end
	local test = UiConfig.StudioTest
	local part = Instance.new("Part")
	part.Name = PROMPT_PART
	part.Anchored = true
	part.CanCollide = false
	part.Size = vector(test.PromptPartSize)
	part.CFrame = origin * CFrame.new(vector(test.PromptOffset))
	local prompt = Prompts.create("Placeholder", part, { name = PROMPT_NAME })
	prompt.Triggered:Connect(function(player: Player)
		local count = ((ServerScriptService:GetAttribute(TRIGGER_COUNT) :: number?) or 0) + 1
		ServerScriptService:SetAttribute(TRIGGER_COUNT, count)
		print(`[HudTestService] placeholder prompt triggered by {player.Name} ({count})`)
		PopupService.show(player, PROMPT_TEXT)
	end)
	part.Parent = Workspace
	print(`[HudTestService] {PROMPT_SWITCH}=true built {part:GetFullName()} at {part.Position}`)
end

local function mirrorButtons(player: Player)
	local wanted = ServerScriptService:GetAttribute(BUTTONS_SWITCH) == true and isTarget(player)
	player:SetAttribute(BUTTONS_SWITCH, wanted)
end

local function bind()
	ensure(TARGET_SWITCH, 0)
	ensure(POPUP_SWITCH, "")
	ensure(PROMPT_SWITCH, false)
	ensure(BUTTONS_SWITCH, false)
	ensure(TRIGGER_COUNT, 0)

	ServerScriptService:GetAttributeChangedSignal(POPUP_SWITCH):Connect(function()
		local value = ServerScriptService:GetAttribute(POPUP_SWITCH)
		if value == "" or value == nil then
			return
		end
		ServerScriptService:SetAttribute(POPUP_SWITCH, "")
		local key, numbers, problem = PopupSwitch.parse(value)
		if key == nil then
			warn(`[HudTestService] {POPUP_SWITCH}: {problem}`)
			return
		end
		for _, player in targets() do
			local sent = PopupService.show(player, key, numbers)
			print(`[HudTestService] {POPUP_SWITCH} {value} -> {player.Name} sent={sent}`)
		end
	end)

	ServerScriptService:GetAttributeChangedSignal(PROMPT_SWITCH):Connect(function()
		if ServerScriptService:GetAttribute(PROMPT_SWITCH) == true then
			buildPrompt()
		else
			removePrompt()
			print(`[HudTestService] {PROMPT_SWITCH}=false removed`)
		end
	end)

	local function mirrorAll()
		for _, player in Players:GetPlayers() do
			mirrorButtons(player)
		end
		print(`[HudTestService] {BUTTONS_SWITCH}={ServerScriptService:GetAttribute(BUTTONS_SWITCH) == true}`)
	end
	ServerScriptService:GetAttributeChangedSignal(BUTTONS_SWITCH):Connect(mirrorAll)
	ServerScriptService:GetAttributeChangedSignal(TARGET_SWITCH):Connect(mirrorAll)
	Players.PlayerAdded:Connect(mirrorButtons)
	for _, player in Players:GetPlayers() do
		mirrorButtons(player)
	end
end

function HudTestService.Start()
	if started then
		return
	end
	started = true
	if not (RunService:IsStudio() and game.PlaceId == 0) or PlaceInfo.Role == "Arena" then
		return
	end
	bind()
	print("[HudTestService] Studio switches bound")
end

return HudTestService

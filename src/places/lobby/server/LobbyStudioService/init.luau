--!strict
-- LobbyStudioService: Studio playtest support for the Lobby (#37, ADR 0015 "Studio playtest
-- support"). Only in Studio at game.PlaceId == 0; on a live server Start does nothing.
-- Switches on ServerScriptService (server command bar, SetAttribute):
--   LobbyTestGeometry  bool    true builds Workspace.Map.LobbyTest and respawns everyone on its
--                              LobbySpawn; false removes it.
--   LobbyTargetUserId  number  the player LobbyStudioReset acts on; 0 = every player.
--   LobbyStudioReset   bool    true resets the group chest claim and the first-join arrow flag of
--                              the target(s) in the live profile; resets itself to false.
-- The other Lobby switches belong to their services: LobbyStudioSimulatorPlayers (PortalService),
-- LobbyStudioGroup (GroupChestService), LobbySimulateVip (VipCornerService),
-- LobbyStudioNextUpdateIn (NewsBoardService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BallConfig = require(Config:WaitForChild("Ball")) :: any
local LobbyConfig = require(Config:WaitForChild("Lobby")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local UiConfig = require(Config:WaitForChild("Ui")) :: any

local GroupChestService = require(script.Parent:WaitForChild("GroupChestService")) :: any
local PortalService = require(script.Parent:WaitForChild("PortalService")) :: any
local TestGeometry = require(script:WaitForChild("TestGeometry"))

local GEOMETRY_SWITCH = "LobbyTestGeometry"
local TARGET_SWITCH = "LobbyTargetUserId"
local RESET_SWITCH = "LobbyStudioReset"

local LobbyStudioService = {}

local studioTools = RunService:IsStudio() and game.PlaceId == 0

local function default(name: string, value: any)
	if ServerScriptService:GetAttribute(name) == nil then
		ServerScriptService:SetAttribute(name, value)
	end
end

local function targets(): { Player }
	local target = ServerScriptService:GetAttribute(TARGET_SWITCH)
	if type(target) == "number" and target ~= 0 then
		local player = Players:GetPlayerByUserId(target)
		if player == nil then
			warn(`[LobbyStudioService] {TARGET_SWITCH}: no player with UserId {target}`)
			return {}
		end
		return { player }
	end
	return Players:GetPlayers()
end

local function setGeometry()
	local enabled = ServerScriptService:GetAttribute(GEOMETRY_SWITCH) == true
	local line = TestGeometry.set({
		test = LobbyConfig.Test,
		display = LobbyConfig.Display,
		map = MapConfig,
		grassTag = BallConfig.Surfaces.Grass,
		vipText = UiConfig.Text.VipCornerSign,
	}, enabled)
	print(`[LobbyStudioService] {line}`)
	if enabled then
		-- Onto the new LobbySpawn, so the default spawn camera looks at the portals (AC1).
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				player:LoadCharacter()
			end)
		end
	end
end

local function reset()
	for _, player in targets() do
		local chest = GroupChestService.StudioResetClaim(player)
		local arrow = PortalService.StudioResetArrow(player)
		print(`[LobbyStudioService] {RESET_SWITCH} {player.Name} ({player.UserId}): chest={chest} arrow={arrow}`)
	end
end

function LobbyStudioService.Start()
	if not studioTools then
		return
	end
	default(GEOMETRY_SWITCH, false)
	default(TARGET_SWITCH, 0)
	default(RESET_SWITCH, false)
	ServerScriptService:GetAttributeChangedSignal(GEOMETRY_SWITCH):Connect(setGeometry)
	ServerScriptService:GetAttributeChangedSignal(RESET_SWITCH):Connect(function()
		if ServerScriptService:GetAttribute(RESET_SWITCH) ~= true then
			return
		end
		ServerScriptService:SetAttribute(RESET_SWITCH, false)
		reset()
	end)
	if ServerScriptService:GetAttribute(GEOMETRY_SWITCH) == true then
		setGeometry()
	end
	print(`[LobbyStudioService] started switches={GEOMETRY_SWITCH},{TARGET_SWITCH},{RESET_SWITCH}`)
end

return LobbyStudioService

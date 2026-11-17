--!strict
-- NewsBoardService: the Lobby news board (concept 7.1; ADR 0009, ADR 0015). Checks the
-- `NewsBoard` parts against the map contract and publishes the time of the next update as the
-- Workspace attribute LobbyNewsNextUpdateAt (Unix seconds, from Config.Lobby.News). The client
-- (NewsBoardController) puts the text on each board's Front face and counts down; the countdown
-- needs no server traffic. Every board shows the same text.
--
-- In Studio at PlaceId 0 the switch LobbyStudioNextUpdateIn sets the next update n seconds from
-- now, so the countdown and its end can be seen in a playtest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyConfig = require(Shared:WaitForChild("Config"):WaitForChild("Lobby")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes"))

local LobbyMap = require(script.Parent:WaitForChild("LobbyMap"))

local MapConfig = LobbyMap.Config

local NEXT_UPDATE_SWITCH = "LobbyStudioNextUpdateIn"

local NewsBoardService = {}

local studioTools = RunService:IsStudio() and game.PlaceId == 0
local started = false

local function configuredNextUpdate(): number
	local at = LobbyConfig.News.NextUpdateAt
	return if type(at) == "number" and at > 0 and at % 1 == 0 then at else 0
end

local function setUpStudio()
	if ServerScriptService:GetAttribute(NEXT_UPDATE_SWITCH) == nil then
		ServerScriptService:SetAttribute(NEXT_UPDATE_SWITCH, 0)
	end
	-- n > 0: next update in n seconds. n < 0: back to the Config value. Resets itself to 0.
	ServerScriptService:GetAttributeChangedSignal(NEXT_UPDATE_SWITCH):Connect(function()
		local value = ServerScriptService:GetAttribute(NEXT_UPDATE_SWITCH)
		if type(value) ~= "number" or value == 0 or value ~= value or math.abs(value) == math.huge then
			return
		end
		ServerScriptService:SetAttribute(NEXT_UPDATE_SWITCH, 0)
		local at = if value > 0 then os.time() + math.floor(value) else configuredNextUpdate()
		Workspace:SetAttribute(LobbyAttributes.NEWS_NEXT_UPDATE_AT, at)
		print(`[NewsBoardService] {NEXT_UPDATE_SWITCH}: next update at {at}`)
	end)
end

local function setUp()
	if started then
		return
	end
	started = true

	Workspace:SetAttribute(LobbyAttributes.NEWS_NEXT_UPDATE_AT, configuredNextUpdate())
	local boards = LobbyMap.bindTag(MapConfig.Tags.NewsBoard, LobbyMap.rules.checkPart, function() end)
	LobbyMap.warnCount(MapConfig.Tags.NewsBoard, #boards(), "some")

	if studioTools then
		setUpStudio()
	end
	print(
		`[NewsBoardService] started boards={#boards()} lastUpdate="{LobbyConfig.News.LastUpdate}" nextUpdateAt={configuredNextUpdate()} studioSwitches={studioTools}`
	)
end

function NewsBoardService.Start()
	setUp()
end

return NewsBoardService

--!strict
-- The first-join arrow (concept 7.1 ✅ decision 14.10., 10.1; ADR 0015). While the server says
-- LobbyShowSingleArrow (from the profile flag tutorial.seenSingleArrow), a pulsing ground arrow
-- runs from the spawn to the Singleplayer portal and the portal's rim pulses. The server clears
-- the flag on the first portal travel, so the arrow never shows again for that player.
--
-- The portal may be streamed out, so the arrow uses the Workspace attributes the server
-- publishes (LobbySpawnPosition, LobbyPortalPositionSingleplayer; ADR 0009 "StreamingEnabled").
-- The rim needs the portal Model and appears when it streams in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LobbyConfig = require(Config:WaitForChild("Lobby")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes"))

local GuideArrow = require(script:WaitForChild("GuideArrow"))

local Display = LobbyConfig.Display
local A = LobbyAttributes

local MODE = "Singleplayer"
local ARROW_NAME = "LobbyGuideSingleplayer"
local RIM_NAME = "LobbyGuideRim"

local GuideArrowController = {}

-- GuideArrow.Style (types of WaitForChild requires are not visible here).
local style = {
	colour = Color3.fromRGB(Display.ArrowRGB[1], Display.ArrowRGB[2], Display.ArrowRGB[3]),
	spacing = Display.ArrowSpacing,
	armSize = Display.ArrowSize,
	height = Display.ArrowHeight,
	gap = Display.ArrowStartGap,
	pulseSeconds = Display.ArrowPulseSeconds,
}

function GuideArrowController.Start()
	local player = Players.LocalPlayer
	local arrow: any = nil
	local rims: { [Instance]: any } = {}

	local function shown(): boolean
		return player:GetAttribute(A.SHOW_SINGLE_ARROW) == true
	end

	local function isTarget(portal: Instance): boolean
		return portal:IsA("Model") and portal:GetAttribute(MapConfig.PortalModeAttribute) == MODE
	end

	local function refreshRim(portal: Instance)
		local rim = rims[portal]
		if shown() and isTarget(portal) and portal.Parent ~= nil then
			if rim == nil then
				rims[portal] = GuideArrow.rim(RIM_NAME, portal :: Model, style)
			end
		elseif rim then
			rim.destroy()
			rims[portal] = nil
		end
	end

	local function refresh()
		if arrow then
			arrow.destroy()
			arrow = nil
		end
		local target = Workspace:GetAttribute(A.PORTAL_POSITION_PREFIX .. MODE)
		local from = Workspace:GetAttribute(A.SPAWN_POSITION)
		if shown() and typeof(target) == "Vector3" and typeof(from) == "Vector3" then
			arrow = GuideArrow.ground(ARROW_NAME, from, target, style)
		end
		for _, portal in CollectionService:GetTagged(MapConfig.Tags.Portal) do
			refreshRim(portal)
		end
	end

	player:GetAttributeChangedSignal(A.SHOW_SINGLE_ARROW):Connect(refresh)
	Workspace:GetAttributeChangedSignal(A.PORTAL_POSITION_PREFIX .. MODE):Connect(refresh)
	Workspace:GetAttributeChangedSignal(A.SPAWN_POSITION):Connect(refresh)
	CollectionService:GetInstanceAddedSignal(MapConfig.Tags.Portal):Connect(refreshRim)
	CollectionService:GetInstanceRemovedSignal(MapConfig.Tags.Portal):Connect(function(portal)
		local rim = rims[portal]
		rims[portal] = nil
		if rim then
			rim.destroy()
		end
	end)
	refresh()
end

return GuideArrowController

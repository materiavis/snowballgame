--!strict
-- Lobby onboarding hints (concept 10.1, #42, ADR 0017). Draws what the server's
-- `TutorialActive` says; this client decides nothing and sends nothing in the Lobby.
--   LobbyMove        0:00, an animated finger on W A S D / the touch joystick / the gamepad stick
--                    (the ground arrow and portal rim of 0:00 are GuideArrowController, ADR 0015)
--   LobbyMultiArrow  next Lobby visit: once a ground arrow to the Multiplayer portal and its rim,
--                    drawn with the same GuideArrow as the first-join arrow
-- Playtest handles: PlayerGui.TutorialHints attributes TutorialShown, TutorialDevice,
-- TutorialGlyph; workspace.LobbyGuideMultiplayer; Highlight TutorialMultiRim on the portal.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LobbyConfig = require(Config:WaitForChild("Lobby")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local TutorialConfig = require(Config:WaitForChild("Tutorial")) :: any
local UiConfig = require(Config:WaitForChild("Ui")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes")) :: any
local TutorialAttributes = require(Shared:WaitForChild("TutorialAttributes"))

local Client = script.Parent.Parent
local InputController = require(Client:WaitForChild("Controllers"):WaitForChild("InputController")) :: any
local Ui = Client:WaitForChild("Ui")
local TutorialControls = require(Ui:WaitForChild("TutorialControls"))
local TutorialHand = require(Ui:WaitForChild("TutorialHand"))
local GuideArrow = require(script.Parent:WaitForChild("GuideArrowController"):WaitForChild("GuideArrow")) :: any

local A = TutorialAttributes
local MODE = "Multiplayer"
local ARROW_NAME = "LobbyGuideMultiplayer"
local RIM_NAME = "TutorialMultiRim"

local TutorialController = {}

-- The first-join arrow's look (Config.Lobby.Display), so both Lobby arrows read alike.
local function arrowStyle(): any
	local d = LobbyConfig.Display
	return {
		colour = Color3.fromRGB(d.ArrowRGB[1], d.ArrowRGB[2], d.ArrowRGB[3]),
		spacing = d.ArrowSpacing,
		armSize = d.ArrowSize,
		height = d.ArrowHeight,
		gap = d.ArrowStartGap,
		pulseSeconds = d.ArrowPulseSeconds,
	}
end

function TutorialController.Start()
	local player = Players.LocalPlayer
	local display = TutorialConfig.Display
	local gui = TutorialHand.gui(display.GuiName, display.DisplayOrder, player:WaitForChild("PlayerGui"))
	local controls = TutorialControls.new({
		gui = gui,
		ui = UiConfig,
		tutorial = TutorialConfig,
		getDevice = InputController.getDevice,
		onDeviceChanged = InputController.onChanged,
	})
	local style = arrowStyle()
	local arrow: any = nil
	local rims: { [Instance]: any } = {}

	local function showing(id: string): boolean
		return A.has(player:GetAttribute(A.ACTIVE), id)
	end

	local function isTarget(portal: Instance): boolean
		return portal:IsA("Model") and portal:GetAttribute(MapConfig.PortalModeAttribute) == MODE
	end

	local function refreshRim(portal: Instance)
		local rim = rims[portal]
		if showing("LobbyMultiArrow") and isTarget(portal) and portal.Parent ~= nil then
			if rim == nil then
				rims[portal] = GuideArrow.rim(RIM_NAME, portal :: Model, style)
			end
		elseif rim then
			rim.destroy()
			rims[portal] = nil
		end
	end

	local drawnFrom: Vector3? = nil
	local drawnTo: Vector3? = nil
	local function refreshArrow()
		local from = Workspace:GetAttribute(LobbyAttributes.SPAWN_POSITION)
		local to = player:GetAttribute(A.TARGET)
		local want = showing("LobbyMultiArrow") and typeof(from) == "Vector3" and typeof(to) == "Vector3"
		if want and arrow and from == drawnFrom and to == drawnTo then
			return
		end
		if arrow then
			arrow.destroy()
			arrow = nil
		end
		if want then
			arrow = GuideArrow.ground(ARROW_NAME, from, to, style)
			drawnFrom, drawnTo = from, to
		end
	end

	local function render()
		controls.setVisible(showing("LobbyMove"))
		refreshArrow()
		for _, portal in CollectionService:GetTagged(MapConfig.Tags.Portal) do
			refreshRim(portal)
		end
		-- What is really drawn (the arrow needs both positions), for the playtest.
		local shown = {}
		if showing("LobbyMove") then
			table.insert(shown, "LobbyMove")
		end
		if arrow then
			table.insert(shown, "LobbyMultiArrow")
		end
		gui:SetAttribute("TutorialShown", A.encode(shown))
	end

	player:GetAttributeChangedSignal(A.ACTIVE):Connect(render)
	player:GetAttributeChangedSignal(A.TARGET):Connect(render)
	Workspace:GetAttributeChangedSignal(LobbyAttributes.SPAWN_POSITION):Connect(render)
	CollectionService:GetInstanceAddedSignal(MapConfig.Tags.Portal):Connect(refreshRim)
	CollectionService:GetInstanceRemovedSignal(MapConfig.Tags.Portal):Connect(function(portal)
		local rim = rims[portal]
		rims[portal] = nil
		if rim then
			rim.destroy()
		end
	end)
	render()
end

return TutorialController

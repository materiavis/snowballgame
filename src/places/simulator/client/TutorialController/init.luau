--!strict
-- Simulator onboarding hints (concept 10.1, #42, ADR 0017). Draws what the server's
-- `TutorialActive` says and where `TutorialTarget` points; it decides nothing. The one report it
-- sends is TutorialHintDone("UpgradesButton") when the Upgrades window opens while that hint
-- shows, because only the client sees a window open.
--   ZoneMove        arrival: the controls finger (TutorialControls) and chevrons ahead of the
--                   own ball in the push direction (workspace.TutorialPushArrow)
--   MaxScale        first MAX: a chevron trail from the character to the scale and a beacon on it
--                   (workspace.TutorialPointer, workspace.TutorialBeacon). "MAX!" and the small
--                   arrow above the ball stay with the HUD and BallGrowthController (#35, #109, 7.4)
--   UpgradesButton  first sale: a ring and an arrow at PlayerGui.SimulatorHud.UpgradesButton and
--                   the key of the last device (UpgradesHint)
--   EggStation      enough Coins for egg 1: trail and beacon to the egg station
--   BarrierPulse    enough Coins for the zone 1 barrier: the Barrier Model pulses (Highlight
--                   TutorialBarrierPulse)
-- Playtest handles: PlayerGui.TutorialHints attributes TutorialShown, TutorialDevice,
-- TutorialGlyph, TutorialMenuGlyph, TutorialReports.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BallConfig = require(Config:WaitForChild("Ball")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local TutorialConfig = require(Config:WaitForChild("Tutorial")) :: any
local UiConfig = require(Config:WaitForChild("Ui")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local TutorialAttributes = require(Shared:WaitForChild("TutorialAttributes"))

local Client = script.Parent.Parent
local Controllers = Client:WaitForChild("Controllers")
local InputController = require(Controllers:WaitForChild("InputController")) :: any
local MenuController = require(Controllers:WaitForChild("MenuController")) :: any
local Ui = Client:WaitForChild("Ui")
local TutorialControls = require(Ui:WaitForChild("TutorialControls"))
local TutorialHand = require(Ui:WaitForChild("TutorialHand"))
local TutorialPointer = require(Ui:WaitForChild("TutorialPointer"))
local TutorialWorld = require(Ui:WaitForChild("TutorialWorld"))
local UpgradesHint = require(script:WaitForChild("UpgradesHint"))

local A = TutorialAttributes
local WORLD_HINTS = { "MaxScale", "EggStation" }

local TutorialController = {}

local function ownBall(userId: number): BasePart?
	local folder = Workspace:FindFirstChild(BallConfig.FolderName)
	if folder == nil then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute(BallConfig.OwnerAttribute) == userId then
			return child
		end
	end
	return nil
end

-- The ZoneIndex of the area (direct child of Workspace.Map) holding `instance`. The area root
-- always replicates (ADR 0009), so a streamed-in station can resolve its zone.
local function zoneOf(instance: Instance): any
	local map = Workspace:FindFirstChild(MapConfig.FolderName)
	local current: Instance? = instance
	while current and current.Parent do
		if current.Parent == map then
			return current:GetAttribute(MapConfig.ZoneIndexAttribute)
		end
		current = current.Parent
	end
	return nil
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
	local upgrades = UpgradesHint.new({
		gui = gui,
		ui = UiConfig,
		tutorial = TutorialConfig,
		hud = player:WaitForChild("PlayerGui"),
		getDevice = InputController.getDevice,
		onDeviceChanged = InputController.onChanged,
	})
	local push: TutorialWorld.Trail? = nil
	local trail: TutorialWorld.Trail? = nil
	local beacon: TutorialWorld.Beacon? = nil
	local pulses: { [Instance]: TutorialWorld.Pulse } = {}
	local reports = 0

	local function showing(id: string): boolean
		return A.has(player:GetAttribute(A.ACTIVE), id)
	end

	local function worldHint(): string?
		for _, id in WORLD_HINTS do
			if showing(id) then
				return id
			end
		end
		return nil
	end

	local function rootAndFeet(): (BasePart?, number)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") then
			local hip = if humanoid then humanoid.HipHeight else 2
			return root, root.Position.Y - root.Size.Y / 2 - hip
		end
		return nil, 0
	end

	local function refreshPulse(model: Instance)
		local pulse = pulses[model]
		local want = showing("BarrierPulse")
			and model:IsA("Model")
			and model.Parent ~= nil
			and zoneOf(model) == TutorialConfig.BarrierZone
		if want and pulse == nil then
			pulses[model] = TutorialWorld.pulse("TutorialBarrierPulse", model :: Model, display)
		elseif not want and pulse then
			pulse.destroy()
			pulses[model] = nil
		end
	end

	local function shownList(): { string }
		local shown = {}
		if showing("ZoneMove") then
			table.insert(shown, "ZoneMove")
		end
		local world = worldHint()
		if world and trail and beacon then
			table.insert(shown, world)
		end
		if upgrades.isShown() then
			table.insert(shown, "UpgradesButton")
		end
		if next(pulses) ~= nil then
			table.insert(shown, "BarrierPulse")
		end
		return shown
	end

	local function render()
		controls.setVisible(showing("ZoneMove"))
		upgrades.setActive(showing("UpgradesButton"))
		if showing("ZoneMove") and push == nil then
			push = TutorialWorld.trail("TutorialPushArrow", display)
		elseif not showing("ZoneMove") and push then
			push.destroy()
			push = nil
		end
		local target = player:GetAttribute(A.TARGET)
		if worldHint() and typeof(target) == "Vector3" then
			if trail == nil then
				trail = TutorialWorld.trail("TutorialPointer", display)
			end
			if beacon == nil then
				beacon = TutorialWorld.beacon("TutorialBeacon", target, display)
			else
				beacon.move(target)
			end
		else
			if trail then
				trail.destroy()
				trail = nil
			end
			if beacon then
				beacon.destroy()
				beacon = nil
			end
		end
		for _, model in CollectionService:GetTagged(MapConfig.Tags.Barrier) do
			refreshPulse(model)
		end
		gui:SetAttribute("TutorialShown", A.encode(shownList()))
	end

	-- The trails follow the character and the ball.
	task.spawn(function()
		while true do
			task.wait(display.WorldRefreshSeconds)
			local root, feet = rootAndFeet()
			if push then
				local ball = ownBall(player.UserId)
				if ball and root then
					local d = ball.Position - root.Position
					push.set(
						TutorialPointer.push(
							ball.Position.X,
							ball.Position.Z,
							d.X,
							d.Z,
							ball.Size.X / 2,
							display.PushCount,
							display.PushSpacing
						),
						ball.Position.Y - ball.Size.Y / 2 + display.TrailHeight
					)
				else
					push.set({}, 0)
				end
			end
			local target = player:GetAttribute(A.TARGET)
			if trail and root and typeof(target) == "Vector3" then
				trail.set(
					TutorialPointer.trail(
						root.Position.X,
						root.Position.Z,
						target.X,
						target.Z,
						display.TrailCount,
						display.TrailSpacing,
						display.TrailStartGap
					),
					feet + display.TrailHeight
				)
			end
		end
	end)

	-- The Upgrades window opening is the one action the server cannot see.
	local remote = Net.waitForRemote("TutorialHintDone") :: RemoteEvent
	local wasOpen = false
	task.spawn(function()
		while true do
			task.wait(display.WindowCheckSeconds)
			local open = MenuController.isOpen("Upgrades")
			upgrades.setWindowOpen(open)
			if open and not wasOpen and showing("UpgradesButton") then
				reports += 1
				gui:SetAttribute("TutorialReports", reports)
				remote:FireServer("UpgradesButton")
			end
			if open ~= wasOpen then
				gui:SetAttribute("TutorialShown", A.encode(shownList()))
			end
			wasOpen = open
		end
	end)

	gui:SetAttribute("TutorialReports", 0)
	player:GetAttributeChangedSignal(A.ACTIVE):Connect(render)
	player:GetAttributeChangedSignal(A.TARGET):Connect(render)
	CollectionService:GetInstanceAddedSignal(MapConfig.Tags.Barrier):Connect(function(model)
		refreshPulse(model)
		gui:SetAttribute("TutorialShown", A.encode(shownList()))
	end)
	CollectionService:GetInstanceRemovedSignal(MapConfig.Tags.Barrier):Connect(function(model)
		local pulse = pulses[model]
		pulses[model] = nil
		if pulse then
			pulse.destroy()
		end
		gui:SetAttribute("TutorialShown", A.encode(shownList()))
	end)
	render()
end

return TutorialController

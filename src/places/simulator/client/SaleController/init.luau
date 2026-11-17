--!strict
-- Sale feedback (concept 7.5, ADR 0012): "+3.4K" that flies to the Coins display. Display only.
-- The server sells and credits the coins; it fires SaleResult with the whole coins of one sale,
-- and this controller shows them with NumberFormat.signed in the pop-up look of #90
-- (Components.popup), then flies the label to PlayerGui.SimulatorHud.Coins. The HUD updates
-- the balance itself from the Coins attribute; nothing here changes the HUD.
--
-- The label lives in its own ScreenGui (Config.Sell.Feedback.GuiName) with the HUD's insets, so
-- its coordinates match the Coins panel. Read-only playtest handles on that gui: SaleFlights,
-- LastSaleCoins, LastSaleText, LastSaleTarget ("Coins" or "None") and LastSaleArrived (the
-- label's centre ended inside the Coins panel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any
local SellConfig = require(Shared:WaitForChild("Config"):WaitForChild("Sell")) :: any
local NetConfig = require(Shared:WaitForChild("Config"):WaitForChild("Net")) :: any

local FlightPath = require(script:WaitForChild("FlightPath"))

local Ui = Theme.Config
local Feedback = SellConfig.Feedback

local REMOTE = "SaleResult"

local SaleController = {}

local started = false
local flights = 0

local function isCoins(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= NetConfig.Sale.MaxCoins
		and value % 1 == 0
end

local function feedbackGui(playerGui: Instance): ScreenGui
	local existing = playerGui:FindFirstChild(Feedback.GuiName)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = Feedback.GuiName
	gui.ResetOnSpawn = false
	-- The same insets as the Simulator HUD, so AbsolutePositions are in the same space.
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Feedback.DisplayOrder
	gui:SetAttribute("SaleFlights", 0)
	gui.Parent = playerGui
	return gui
end

local function coinsPanel(playerGui: Instance): GuiObject?
	local hud = playerGui:FindFirstChild(Feedback.HudGuiName)
	local panel = hud and hud:FindFirstChild(Feedback.CoinsPanelName)
	return if panel and panel:IsA("GuiObject") then panel else nil
end

local function fadeOut(label: TextLabel)
	local info = TweenInfo.new(Feedback.FadeSeconds)
	local fade = TweenService:Create(label, info, { TextTransparency = 1, BackgroundTransparency = 1 })
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") then
			TweenService:Create(child, info, { Transparency = 1 }):Play()
		end
	end
	fade.Completed:Connect(function()
		label:Destroy()
	end)
	fade:Play()
end

local function fly(coins: number)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = feedbackGui(playerGui)
	local size = gui.AbsoluteSize
	local scale = Layout.scale({ width = size.X, height = size.Y, touch = UserInputService.TouchEnabled }, Ui)
	local width, height = Layout.px(Feedback.Width, scale), Layout.px(Feedback.Height, scale)

	local label = Components.popup(Feedback.LabelName)
	label.AutoLocalize = false
	label.Text = NumberFormat.signed(coins)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(width, height)
	Components.scaleText(label, scale)
	local from = FlightPath.start(size.X, size.Y, Feedback.StartYFraction)
	label.Position = UDim2.fromOffset(from.x, from.y)
	label.Visible = true
	label:SetAttribute("Coins", coins)
	label.Parent = gui

	flights += 1
	gui:SetAttribute("SaleFlights", flights)
	gui:SetAttribute("LastSaleCoins", coins)
	gui:SetAttribute("LastSaleText", label.Text)
	gui:SetAttribute("LastSaleArrived", false)

	task.delay(Feedback.ShowSeconds, function()
		if label.Parent == nil then
			return
		end
		-- Read the panel now: the HUD may have relaid out since the sale.
		local panel = coinsPanel(playerGui)
		local target = if panel
			then FlightPath.target(
				panel.AbsolutePosition.X,
				panel.AbsolutePosition.Y,
				panel.AbsoluteSize.X,
				panel.AbsoluteSize.Y,
				gui.AbsolutePosition.X,
				gui.AbsolutePosition.Y
			)
			else { x = from.x, y = 0 }
		gui:SetAttribute("LastSaleTarget", if panel then Feedback.CoinsPanelName else "None")
		local tween = TweenService:Create(
			label,
			TweenInfo.new(Feedback.FlySeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Position = UDim2.fromOffset(target.x, target.y),
				Size = UDim2.fromOffset(width * Feedback.EndScale, height * Feedback.EndScale),
			}
		)
		tween.Completed:Connect(function()
			if panel and panel.Parent then
				local centre = label.AbsolutePosition + label.AbsoluteSize / 2
				local arrived = FlightPath.inside(
					{ x = centre.X, y = centre.Y },
					panel.AbsolutePosition.X,
					panel.AbsolutePosition.Y,
					panel.AbsoluteSize.X,
					panel.AbsoluteSize.Y
				)
				gui:SetAttribute("LastSaleArrived", arrived)
			end
			fadeOut(label)
		end)
		tween:Play()
	end)
end

function SaleController.Start()
	if started then
		return
	end
	started = true
	local remote = Net.waitForRemote(REMOTE) :: any
	remote.OnClientEvent:Connect(function(coins: any)
		if isCoins(coins) then
			fly(coins)
		end
	end)
end

return SaleController

--!strict
-- Content of the Upgrades window (concept 7.8, ADR 0008 `UpgradesWindow.Content`, ADR 0010):
-- one row per upgrade with name, level x/MaxLevel, effect now -> after the next level, the price
-- and a buy button. Rows scroll, so the window can stay small on phones.
--
-- Display only. Levels, coins and the load status are server-written player attributes; the
-- buy button sends only the upgrade id through the UpgradeBuy remote, and the server decides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpgradesConfig = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any
local UpgradeAttributes = require(Shared:WaitForChild("UpgradeAttributes"))
local UpgradesView = require(script.Parent:WaitForChild("UpgradesView"))

local Ui = Theme.Config

local REMOTE = "UpgradeBuy"
local COINS_ATTRIBUTE = "Coins"
local STATUS_ATTRIBUTE = "DataLoadStatus"

export type Panel = {
	-- Positions the rows for the window content's width.
	layout: (width: number, button: number, scale: number) -> (),
}

type RowView = {
	frame: Frame,
	name: TextLabel,
	level: TextLabel,
	effect: TextLabel,
	price: TextLabel,
	buy: TextButton,
	canBuy: boolean,
}

local UpgradesPanel = {}

function UpgradesPanel.build(content: Frame): Panel
	local player = Players.LocalPlayer
	local z = Ui.ZIndex.Window + 2

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = Ui.UpgradesWindow.ScrollBarThickness
	scroll.Selectable = false
	scroll.ZIndex = z
	scroll.Parent = content

	local remote: RemoteEvent? = nil
	task.spawn(function()
		remote = Net.waitForRemote(REMOTE) :: RemoteEvent
	end)

	local views: { [string]: RowView } = {}
	for index, id in UpgradesConfig.Order do
		local frame = Instance.new("Frame")
		frame.Name = id
		frame.BackgroundTransparency = 1
		frame.LayoutOrder = index
		frame.ZIndex = z
		frame.Parent = scroll

		local name = Components.label("Name", Ui.UpgradeRows[id].Name, Ui.TextSize.Body, z + 1, { bold = true })
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = frame
		local level = Components.label("Level", Ui.Text.Missing, Ui.TextSize.Body, z + 1, { autoLocalize = false })
		level.TextXAlignment = Enum.TextXAlignment.Right
		level.Parent = frame
		local effect = Components.label("Effect", Ui.Text.Missing, Ui.TextSize.Caption, z + 1, {
			muted = true,
			autoLocalize = false,
		})
		effect.TextXAlignment = Enum.TextXAlignment.Left
		effect.Parent = frame
		local price = Components.label("Price", Ui.Text.Missing, Ui.TextSize.Body, z + 1, {
			bold = true,
			autoLocalize = false,
		})
		price.Parent = frame
		local buy = Components.button("Buy", Ui.Text.UpgradeBuy, z + 1)
		buy.Parent = frame

		local view: RowView = {
			frame = frame,
			name = name,
			level = level,
			effect = effect,
			price = price,
			buy = buy,
			canBuy = false,
		}
		views[id] = view

		buy.Activated:Connect(function()
			-- Only the id is sent. A click the server refuses changes nothing.
			if view.canBuy and remote then
				remote:FireServer(id)
			end
		end)
	end

	local function refresh()
		local levels: { [string]: any } = {}
		for _, id in UpgradesConfig.Order do
			levels[id] = player:GetAttribute(UpgradeAttributes.level(id))
		end
		local rows = UpgradesView.rows({
			upgrades = UpgradesConfig,
			formulas = Formulas.Upgrades,
			formatPrice = NumberFormat.price,
			ui = Ui,
			status = player:GetAttribute(STATUS_ATTRIBUTE),
			coins = player:GetAttribute(COINS_ATTRIBUTE),
			levels = levels,
		})
		for _, row in rows do
			local view = views[row.id]
			view.level.Text = row.levelText
			view.effect.Text = row.effectText
			view.price.Text = row.priceText
			view.buy.Text = row.buttonText
			view.buy.Visible = row.state ~= "Max"
			view.buy.AutoButtonColor = row.canBuy
			view.buy.BackgroundColor3 = if row.canBuy then Theme.Brand else Theme.SurfaceRaised
			view.buy.TextColor3 = if row.canBuy then Theme.Text else Theme.TextMuted
			view.canBuy = row.canBuy
		end
	end

	local function layout(width: number, button: number, scale: number)
		local rowWidth = math.max(0, width - scroll.ScrollBarThickness)
		local r = UpgradesView.layout(rowWidth, button, scale, Ui)
		local y = 0
		for _, id in UpgradesConfig.Order do
			local view = views[id]
			Components.place(view.frame, { x = 0, y = y, width = rowWidth, height = r.height })
			Components.place(view.name, r.name)
			Components.place(view.level, r.level)
			Components.place(view.effect, r.effect)
			Components.place(view.price, r.price)
			Components.place(view.buy, r.buy)
			y += r.height + r.gap
		end
		scroll.CanvasSize = UDim2.fromOffset(0, math.max(0, y - r.gap))
		Components.scaleText(scroll, scale)
	end

	player:GetAttributeChangedSignal(COINS_ATTRIBUTE):Connect(refresh)
	player:GetAttributeChangedSignal(STATUS_ATTRIBUTE):Connect(refresh)
	for _, id in UpgradesConfig.Order do
		player:GetAttributeChangedSignal(UpgradeAttributes.level(id)):Connect(refresh)
	end
	refresh()

	return table.freeze({ layout = layout })
end

return table.freeze(UpgradesPanel)

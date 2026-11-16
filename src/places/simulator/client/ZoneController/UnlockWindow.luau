--!strict
-- The barrier unlock window (#39, concept 7.6: "Zone 6 freischalten für 3.7M?" with Yes and
-- No). Opens when this player walks into a barrier they can afford, or uses its prompt. Yes
-- sends only the zone number (ZoneRequests); the server checks and charges, and the barrier
-- opens once the server's ZonesUnlocked attribute lists the zone.
--
-- Playtest handles: PlayerGui.ZoneHud.ZoneUnlockWindow (attribute Zone) with Content.Question,
-- Content.Yes and Content.No.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local ZoneUi = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ZoneUi")) :: any
local ZoneRequests = require(script.Parent:WaitForChild("ZoneRequests"))
local ZoneView = require(script.Parent:WaitForChild("ZoneView"))

export type UnlockWindow = {
	window: Components.Window,
	-- Fills the question for `zone` at `priceText` (NumberFormat.price) before it opens.
	prepare: (zone: number, priceText: string) -> (),
	layout: (contentWidth: number, button: number, scale: number) -> (),
}

local Ui = Theme.Config
local config = ZoneUi.UnlockWindow

local UnlockWindow = {}

-- `close` closes this window through MenuController.
function UnlockWindow.build(close: () -> ()): UnlockWindow
	local window = Components.window("ZoneUnlockWindow", Ui.Text.ZoneUnlockTitle)
	local z = Ui.ZIndex.Window + 2
	local question = Components.label("Question", "", Ui.TextSize.Body, z, { autoLocalize = false })
	question.Parent = window.content
	local yes = Components.button("Yes", Ui.Text.ZoneUnlockYes, z, true)
	yes.Parent = window.content
	local no = Components.button("No", Ui.Text.ZoneUnlockNo, z)
	no.Parent = window.content

	local zone: number? = nil

	yes.Activated:Connect(function()
		local target = zone
		close()
		if target then
			ZoneRequests.unlock(target)
		end
	end)
	no.Activated:Connect(close)
	window.close.Activated:Connect(close)

	local function prepare(nextZone: number, priceText: string)
		zone = nextZone
		window.root:SetAttribute("Zone", nextZone)
		question.Text = ZoneView.question(nextZone, priceText, Ui.Text)
	end

	local function layout(contentWidth: number, button: number, scale: number)
		local gap = Layout.px(config.Gap, scale)
		local questionHeight = config.QuestionRows * button
		Components.place(question, { x = 0, y = 0, width = contentWidth, height = questionHeight })
		local half = math.max(0, math.floor((contentWidth - gap) / 2))
		local y = questionHeight + gap
		Components.place(yes, { x = 0, y = y, width = half, height = button })
		Components.place(no, { x = contentWidth - half, y = y, width = half, height = button })
	end

	return { window = window, prepare = prepare, layout = layout }
end

return table.freeze(UnlockWindow)

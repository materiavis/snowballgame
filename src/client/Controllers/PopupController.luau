--!strict
-- Short centre pop-ups (concept 10.2, #90, ADR 0008), e.g. "MAX!", "+3.4K", "New Pet!" once the
-- features that trigger them exist (#109, #38, #41). Display only.
-- Two ways in, both with a text key from Config.Ui.PopupTexts and optional numbers (never free
-- text): PopupController.show() for client callers, and the server-to-client Popup remote that
-- PopupService fires. Nothing is sent to the server.
-- A Place HUD attaches its ScreenGui and places the pop-up from Layout.popup. Until a HUD
-- attaches (Arena: #91), pop-ups are dropped, so this controller shows nothing there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiFolder = script.Parent.Parent:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Layout = require(UiFolder:WaitForChild("Layout"))
local PopupQueue = require(UiFolder:WaitForChild("PopupQueue"))
local Theme = require(UiFolder:WaitForChild("Theme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local NetConfig = require(Shared:WaitForChild("Config"):WaitForChild("Net")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any
local PopupText = require(Shared:WaitForChild("PopupText"))

local Ui = Theme.Config

local REMOTE = "Popup"
local LABEL_NAME = "Popup"

type Entry = { text: string, autoLocalize: boolean }

local PopupController = {}

local queue = PopupQueue.new(Ui.Popup.DurationSeconds, Ui.Popup.MaxQueued) :: PopupQueue.PopupQueue<Entry>
local label: TextLabel? = nil
local timerToken = 0
local started = false

local function render()
	local entry = queue.current(os.clock())
	local current = label
	if current then
		current.Visible = entry ~= nil
		if entry then
			current.AutoLocalize = entry.autoLocalize
			current.Text = entry.text
		end
	end
	local endsAt = queue.endsAt()
	timerToken += 1
	if endsAt then
		local token = timerToken
		task.delay(math.max(0, endsAt - os.clock()), function()
			if token == timerToken then
				render()
			end
		end)
	end
end

-- Shows Config.Ui.Text[key] with {1}, {2} replaced by `numbers` (NumberFormat.number). Returns
-- false, and shows nothing, for a key outside Config.Ui.PopupTexts, wrong numbers, or while
-- no HUD is attached.
function PopupController.show(key: string, numbers: { number }?): boolean
	if label == nil then
		return false
	end
	local list = numbers or {}
	local text = PopupText.format(key, list, Ui, NetConfig.Popup, NumberFormat.number)
	if text == nil then
		warn(`[PopupController] refused pop-up {tostring(key)}`)
		return false
	end
	queue.push({ text = text, autoLocalize = not PopupText.hasNumbers(key, Ui) }, os.clock())
	render()
	return true
end

-- Creates the pop-up label in a Place HUD's ScreenGui. One HUD per Place; a second attach moves
-- the pop-up to the new gui.
function PopupController.attach(gui: ScreenGui)
	if label then
		label:Destroy()
	end
	local created = Components.popup(LABEL_NAME)
	created.Parent = gui
	label = created
	render()
end

-- Called by the HUD's relayout with Layout.popup(...).rect.
function PopupController.place(rect: Layout.Rect, scale: number)
	local current = label
	if current then
		Components.place(current, rect)
		Components.scaleText(current, scale)
	end
end

function PopupController.Start()
	if started then
		return
	end
	started = true
	local remote = Net.waitForRemote(REMOTE) :: RemoteEvent
	remote.OnClientEvent:Connect(function(key: any, ...: any)
		local numbers = PopupText.collect(...)
		if type(key) ~= "string" or numbers == nil then
			return
		end
		PopupController.show(key, numbers :: { number })
	end)
end

return PopupController

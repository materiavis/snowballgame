--!strict
-- Window stack, menu keys and the left-edge button registry (concept 10.2, ADR 0008). A Place
-- HUD registers its windows; this controller opens and closes them, binds each window's menu
-- keys and binds gamepad B to close the top window. Nothing is bound and nothing is shown until
-- a window or button is registered, so Places without them are unaffected. B is bound only
-- while a window is open.
-- Left-edge buttons (#90): a feature calls registerButton once its window or action exists
-- (owner decision 2026-11-16: hidden until then). The button's keys (Config.Ui.Keybinds[id])
-- are bound only while it is registered. The Place HUD draws the visible buttons.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiFolder = script.Parent.Parent:WaitForChild("Ui")
local ButtonRegistry = require(UiFolder:WaitForChild("ButtonRegistry"))
local WindowStack = require(UiFolder:WaitForChild("WindowStack"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ui")) :: any

export type WindowSpec = {
	id: string,
	root: GuiObject,
	-- Shows or hides the window. Called by the stack only.
	setOpen: (open: boolean) -> (),
	-- What gamepad selection jumps to when the window opens (e.g. its close button).
	selection: GuiObject?,
	-- Enum.KeyCode names (Config.Ui.Keybinds): toggle keys open or close, open keys only open.
	-- A window with a left-edge button leaves these out: registerButton binds its keys.
	toggleKeys: { string }?,
	openKeys: { string }?,
}

-- A left-edge button. `id` is one of Config.Ui.LeftButtons. Give either `window` (a registered
-- window id: the button and the toggle keys toggle it, the open keys open it) or `activate`
-- (an action such as a teleport: the button and every key of the button run it).
export type ButtonSpec = {
	id: string,
	window: string?,
	activate: (() -> ())?,
}

local MenuController = {}

local CLOSE_ACTION = "MenuCloseTop"

local specs: { [string]: WindowSpec } = {}
local closeBound = false
local buttons = ButtonRegistry.new(UiConfig.LeftButtons)
local buttonSpecs: { [string]: ButtonSpec } = {}
local buttonListeners: { [number]: () -> () } = {}
local nextButtonListener = 0

local function keyCodes(names: { string }?): { Enum.KeyCode }
	local codes = {}
	for _, name in names or {} do
		table.insert(codes, (Enum.KeyCode :: any)[name])
	end
	return codes
end

local function selectTop(top: string?)
	if InputController.getDevice() ~= "Gamepad" then
		return
	end
	local spec = top and specs[top]
	GuiService.SelectedObject = if spec then spec.selection else nil
end

-- Forward declared: the close action and the stack's onChange refer to each other.
local stack: WindowStack.WindowStack

local function onCloseAction(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if stack.closeTop() then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function updateCloseBinding()
	local shouldBind = stack.count() > 0
	if shouldBind == closeBound then
		return
	end
	closeBound = shouldBind
	if shouldBind then
		ContextActionService:BindActionAtPriority(
			CLOSE_ACTION,
			onCloseAction,
			false,
			UiConfig.ActionPriority,
			table.unpack(keyCodes(UiConfig.Keybinds.CloseTop))
		)
	else
		ContextActionService:UnbindAction(CLOSE_ACTION)
	end
end

stack = WindowStack.new(function(id: string, isOpen: boolean)
	local spec = specs[id]
	if spec then
		spec.setOpen(isOpen)
		if not isOpen then
			local selected = GuiService.SelectedObject
			if selected and (selected == spec.root or selected:IsDescendantOf(spec.root)) then
				GuiService.SelectedObject = nil
			end
		end
	end
	updateCloseBinding()
	selectTop(stack.top())
end)

type KeyActions = {
	toggle: () -> (),
	open: () -> (),
	-- Open keys pass (do nothing) while this is false, e.g. while the window is already open.
	canOpen: () -> boolean,
}

-- Toggle keys always sink. Open keys (D-pad) also move gamepad selection, so they pass while
-- any GUI object is selected or canOpen() is false. Action names are MenuToggle<id> and
-- MenuOpen<id>.
local function bindKeys(id: string, toggleNames: { string }?, openNames: { string }?, actions: KeyActions)
	local toggleCodes = keyCodes(toggleNames)
	if #toggleCodes > 0 then
		ContextActionService:BindActionAtPriority(`MenuToggle{id}`, function(_name, state)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			actions.toggle()
			return Enum.ContextActionResult.Sink
		end, false, UiConfig.ActionPriority, table.unpack(toggleCodes))
	end

	local openCodes = keyCodes(openNames)
	if #openCodes > 0 then
		ContextActionService:BindActionAtPriority(`MenuOpen{id}`, function(_name, state)
			if state ~= Enum.UserInputState.Begin or GuiService.SelectedObject ~= nil or not actions.canOpen() then
				return Enum.ContextActionResult.Pass
			end
			actions.open()
			return Enum.ContextActionResult.Sink
		end, false, UiConfig.ActionPriority, table.unpack(openCodes))
	end
end

local function windowActions(window: string): KeyActions
	return {
		toggle = function()
			stack.toggle(window)
		end,
		open = function()
			stack.open(window)
		end,
		canOpen = function(): boolean
			return not stack.isOpen(window)
		end,
	}
end

local function notifyButtons()
	for _, listener in table.clone(buttonListeners) do
		task.spawn(listener)
	end
end

function MenuController.open(id: string)
	assert(specs[id], `MenuController: unknown window {id}`)
	if not stack.open(id) then
		-- Already open: it moved to the top, so selection follows it.
		selectTop(stack.top())
	end
end

function MenuController.close(id: string)
	stack.close(id)
end

function MenuController.toggle(id: string)
	assert(specs[id], `MenuController: unknown window {id}`)
	stack.toggle(id)
end

function MenuController.closeTop(): string?
	return stack.closeTop()
end

function MenuController.isOpen(id: string): boolean
	return stack.isOpen(id)
end

function MenuController.top(): string?
	return stack.top()
end

function MenuController.register(spec: WindowSpec)
	assert(specs[spec.id] == nil, `MenuController: window {spec.id} registered twice`)
	specs[spec.id] = spec
	spec.setOpen(false)
	bindKeys(spec.id, spec.toggleKeys, spec.openKeys, windowActions(spec.id))
end

-- Shows a left-edge button and binds its keys. Returns a function that hides it again and
-- unbinds the keys. Errors on an unknown id, a second registration, or a spec without exactly
-- one of window and activate.
function MenuController.registerButton(spec: ButtonSpec): () -> ()
	assert((spec.window == nil) ~= (spec.activate == nil), `MenuController: button {spec.id} needs window or activate`)
	local window = spec.window
	if window then
		assert(specs[window], `MenuController: button {spec.id} names unknown window {window}`)
	end
	buttons.register(spec.id)
	buttonSpecs[spec.id] = spec

	local keys = UiConfig.Keybinds[spec.id]
	local actions: KeyActions
	if window then
		actions = windowActions(window)
	else
		local activate = spec.activate :: () -> ()
		actions = {
			toggle = activate,
			open = activate,
			canOpen = function(): boolean
				return true
			end,
		}
	end
	bindKeys(spec.id, keys and keys.Toggle, keys and keys.Open, actions)
	notifyButtons()

	local done = false
	return function()
		if done then
			return
		end
		done = true
		ContextActionService:UnbindAction(`MenuToggle{spec.id}`)
		ContextActionService:UnbindAction(`MenuOpen{spec.id}`)
		buttons.unregister(spec.id)
		buttonSpecs[spec.id] = nil
		notifyButtons()
	end
end

-- What a click on the button does: toggles its window or runs its action.
function MenuController.activateButton(id: string)
	local spec = buttonSpecs[id]
	if spec == nil then
		return
	end
	if spec.window then
		stack.toggle(spec.window)
	elseif spec.activate then
		spec.activate()
	end
end

-- Registered button ids in Config.Ui.LeftButtons order.
function MenuController.visibleButtons(): { string }
	return buttons.visible()
end

-- Calls fn() after a button was registered or unregistered. Returns a disconnect function.
function MenuController.onButtonsChanged(fn: () -> ()): () -> ()
	nextButtonListener += 1
	local id = nextButtonListener
	buttonListeners[id] = fn
	return function()
		buttonListeners[id] = nil
	end
end

function MenuController.Start()
	-- A player who picks up a gamepad while a window is open lands on that window.
	InputController.onChanged(function(device)
		if device == "Gamepad" and stack.top() then
			selectTop(stack.top())
		end
	end)
end

return MenuController

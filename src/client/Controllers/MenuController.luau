--!strict
-- Window stack and menu keys (concept 10.2, ADR 0008). A Place HUD registers its windows; this
-- controller opens and closes them, binds each window's menu keys and binds gamepad B to
-- close the top window. Nothing is bound and nothing is shown until a window is registered,
-- so Places without windows are unaffected. B is bound only while a window is open.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiFolder = script.Parent.Parent:WaitForChild("Ui")
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
	toggleKeys: { string }?,
	openKeys: { string }?,
}

local MenuController = {}

local CLOSE_ACTION = "MenuCloseTop"

local specs: { [string]: WindowSpec } = {}
local closeBound = false

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

	local toggleCodes = keyCodes(spec.toggleKeys)
	if #toggleCodes > 0 then
		ContextActionService:BindActionAtPriority(`MenuToggle{spec.id}`, function(_name, state)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			stack.toggle(spec.id)
			return Enum.ContextActionResult.Sink
		end, false, UiConfig.ActionPriority, table.unpack(toggleCodes))
	end

	-- Open-only keys (D-pad) also move gamepad selection, so they pass while the window is
	-- open or any GUI object is selected.
	local openCodes = keyCodes(spec.openKeys)
	if #openCodes > 0 then
		ContextActionService:BindActionAtPriority(`MenuOpen{spec.id}`, function(_name, state)
			if state ~= Enum.UserInputState.Begin or GuiService.SelectedObject ~= nil or stack.isOpen(spec.id) then
				return Enum.ContextActionResult.Pass
			end
			stack.open(spec.id)
			return Enum.ContextActionResult.Sink
		end, false, UiConfig.ActionPriority, table.unpack(openCodes))
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

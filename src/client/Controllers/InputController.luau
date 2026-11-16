--!strict
-- Tracks the most recently used input device (concept 3.2, ADR 0008) for prompts and gamepad
-- selection. No UI of its own, so it is inert in every Place; prompts that use it come with #90.

local UserInputService = game:GetService("UserInputService")

local InputDevice = require(script.Parent.Parent:WaitForChild("Ui"):WaitForChild("InputDevice"))

export type Device = InputDevice.Device

local InputController = {}

local listeners: { [number]: (Device) -> () } = {}
local nextListener = 0
local started = false
local device: Device = InputDevice.initial(
	UserInputService:GetLastInputType().Name,
	#UserInputService:GetConnectedGamepads() > 0,
	UserInputService.TouchEnabled
)

local function setDevice(newDevice: Device)
	if newDevice == device then
		return
	end
	device = newDevice
	for _, listener in table.clone(listeners) do
		task.spawn(listener, newDevice)
	end
end

function InputController.getDevice(): Device
	return device
end

-- Calls fn(device) whenever the device family changes. Returns a function that disconnects.
function InputController.onChanged(fn: (Device) -> ()): () -> ()
	nextListener += 1
	local id = nextListener
	listeners[id] = fn
	return function()
		listeners[id] = nil
	end
end

function InputController.Start()
	if started then
		return
	end
	started = true
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local newDevice = InputDevice.fromInputType(inputType.Name)
		if newDevice then
			setDevice(newDevice)
		end
	end)
end

return InputController

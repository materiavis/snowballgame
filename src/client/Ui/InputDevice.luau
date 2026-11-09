--!strict
-- Maps a Roblox UserInputType name to the device family a prompt should show (concept 3.2,
-- ADR 0008). Pure, so it takes the Enum item's Name instead of the Enum.

export type Device = "Touch" | "KeyboardMouse" | "Gamepad"

local KEYBOARD_MOUSE: { [string]: boolean } = {
	Keyboard = true,
	TextInput = true,
	MouseButton1 = true,
	MouseButton2 = true,
	MouseButton3 = true,
	MouseMovement = true,
	MouseWheel = true,
}

local InputDevice = {}

-- Returns nil for inputs that say nothing about the device in hand (Focus, Gyro, None …),
-- so the last known device stays.
function InputDevice.fromInputType(name: string): Device?
	if name == "Touch" then
		return "Touch"
	elseif KEYBOARD_MOUSE[name] then
		return "KeyboardMouse"
	elseif string.match(name, "^Gamepad%d+$") then
		return "Gamepad"
	end
	return nil
end

-- Best guess before the first input: the last input type if it names a device, then a
-- connected gamepad, then touch, then keyboard and mouse.
function InputDevice.initial(lastInputType: string, gamepadConnected: boolean, touchEnabled: boolean): Device
	local fromLast = InputDevice.fromInputType(lastInputType)
	if fromLast then
		return fromLast
	elseif gamepadConnected then
		return "Gamepad"
	elseif touchEnabled then
		return "Touch"
	end
	return "KeyboardMouse"
end

return table.freeze(InputDevice)

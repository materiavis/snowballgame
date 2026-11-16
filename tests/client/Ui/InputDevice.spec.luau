--!strict
-- Last-used input device classification (concept 3.2, ADR 0008).

local T = require("../../TestKit")
local InputDevice = require("../../../src/client/Ui/InputDevice")

return T.suite("Ui InputDevice (3.2)", function(test)
	test("maps input types to touch, keyboard and mouse, or gamepad", function()
		T.equal(InputDevice.fromInputType("Touch"), "Touch")
		T.equal(InputDevice.fromInputType("Keyboard"), "KeyboardMouse")
		T.equal(InputDevice.fromInputType("MouseButton1"), "KeyboardMouse")
		T.equal(InputDevice.fromInputType("MouseMovement"), "KeyboardMouse")
		T.equal(InputDevice.fromInputType("MouseWheel"), "KeyboardMouse")
		T.equal(InputDevice.fromInputType("Gamepad1"), "Gamepad")
		T.equal(InputDevice.fromInputType("Gamepad8"), "Gamepad")
	end)

	test("inputs that say nothing about the device keep the last one", function()
		T.equal(InputDevice.fromInputType("Focus"), nil)
		T.equal(InputDevice.fromInputType("Gyro"), nil)
		T.equal(InputDevice.fromInputType("Accelerometer"), nil)
		T.equal(InputDevice.fromInputType("None"), nil)
		T.equal(InputDevice.fromInputType("GamepadX"), nil)
	end)

	test("initial guess: last input, then gamepad, then touch, then keyboard", function()
		T.equal(InputDevice.initial("Touch", true, true), "Touch")
		T.equal(InputDevice.initial("None", true, true), "Gamepad")
		T.equal(InputDevice.initial("None", false, true), "Touch")
		T.equal(InputDevice.initial("None", false, false), "KeyboardMouse")
	end)
end)

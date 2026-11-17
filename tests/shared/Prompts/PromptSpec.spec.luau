--!strict
-- #90 prompt wrapper (concept 3.2): presets of Config.Ui.Prompts resolve to ProximityPrompt
-- values; texts come from Config.Ui.Text; broken presets fail loudly.

local T = require("../../TestKit")
local PromptSpec = require("../../../src/shared/Prompts/PromptSpec")
local Ui = require("../../../src/shared/Config/Ui") :: any

local function withPrompts(prompts: any): any
	local ui = table.clone(Ui)
	ui.Prompts = prompts
	return ui
end

return T.suite("Prompts PromptSpec (#90)", function(test)
	test("the placeholder preset takes Default's keys and its own texts", function()
		local spec = PromptSpec.resolve("Placeholder", Ui)
		T.equal(spec.KeyboardKeyCode, Ui.Prompts.Default.KeyboardKeyCode)
		T.equal(spec.GamepadKeyCode, Ui.Prompts.Default.GamepadKeyCode)
		T.equal(spec.HoldDuration, Ui.Prompts.Default.HoldDuration)
		T.equal(spec.MaxActivationDistance, Ui.Prompts.Default.MaxActivationDistance)
		T.equal(spec.RequiresLineOfSight, false)
		T.equal(spec.ActionText, Ui.Text.PromptTestAction)
		T.equal(spec.ObjectText, Ui.Text.PromptTestObject)
	end)

	test("default keys: E on the keyboard, X on the gamepad", function()
		T.equal(Ui.Prompts.Default.KeyboardKeyCode, "E")
		T.equal(Ui.Prompts.Default.GamepadKeyCode, "ButtonX")
	end)

	test("a preset overrides Default field by field", function()
		local ui = withPrompts({
			Default = Ui.Prompts.Default,
			Hold = { HoldDuration = 1.5, KeyboardKeyCode = "F", ActionText = "PopupTest" },
		})
		local spec = PromptSpec.resolve("Hold", ui)
		T.equal(spec.HoldDuration, 1.5)
		T.equal(spec.KeyboardKeyCode, "F")
		T.equal(spec.GamepadKeyCode, "ButtonX")
		T.equal(spec.ActionText, Ui.Text.PopupTest)
		T.equal(spec.ObjectText, "")
	end)

	test("unknown presets, unknown text keys and bad numbers fail loudly", function()
		T.throws(function()
			PromptSpec.resolve("Nope", Ui)
		end, "unknown preset")
		local function broken(preset: any): string
			return T.throws(function()
				PromptSpec.resolve("Broken", withPrompts({ Default = Ui.Prompts.Default, Broken = preset }))
			end)
		end
		T.isTrue(string.find(broken({ ActionText = "NoSuchKey" }), "Config.Ui.Text", 1, true) ~= nil)
		T.isTrue(string.find(broken({ HoldDuration = -1 }), "HoldDuration", 1, true) ~= nil)
		T.isTrue(string.find(broken({ MaxActivationDistance = 0 }), "MaxActivationDistance", 1, true) ~= nil)
		T.isTrue(string.find(broken({ KeyboardKeyCode = "" }), "KeyboardKeyCode", 1, true) ~= nil)
		T.isTrue(string.find(broken({ RequiresLineOfSight = "yes" }), "RequiresLineOfSight", 1, true) ~= nil)
	end)
end)

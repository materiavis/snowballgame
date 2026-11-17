--!strict
-- #90 pop-up texts: only keys from Config.Ui.PopupTexts plus bounded numbers, formatted with
-- NumberFormat.number; no free text. The Popup remote's schema matches Config.Net.Popup.

local T = require("../TestKit")
local E = require("../helpers/Economy")
local PopupText = require("../../src/shared/PopupText")
local Ui = require("../../src/shared/Config/Ui") :: any
local NetConfig = require("../../src/shared/Config/Net") :: any
local UpgradesConfig = require("../../src/shared/Config/Upgrades") :: any
local Schema = require("../../src/shared/Net/Schema")
local Registry = require("../../src/shared/Net/Registry")
local declareRemotes = require("../../src/shared/Net/Remotes")

local limits = NetConfig.Popup
local format = E.NumberFormat.number

return T.suite("PopupText (#90)", function(test)
	test("every pop-up key has an English text", function()
		for _, key in Ui.PopupTexts do
			T.equal(type(Ui.Text[key]), "string", key)
		end
	end)

	test("a plain key formats to its text", function()
		T.equal(PopupText.format("PopupTest", {}, Ui, limits, format), Ui.Text.PopupTest)
		T.equal(PopupText.hasNumbers("PopupTest", Ui), false)
	end)

	test("numbers are abbreviated with K, M, B ... like every other number", function()
		T.equal(PopupText.format("PopupTestNumber", { 3400 }, Ui, limits, format), "+3.4K")
		T.equal(PopupText.format("PopupTestNumber", { 3755901 }, Ui, limits, format), "+3.7M")
		T.equal(PopupText.format("PopupTestNumber", { 12 }, Ui, limits, format), "+12")
		T.equal(PopupText.hasNumbers("PopupTestNumber", Ui), true)
	end)

	test("free text, unknown keys and keys outside the pop-up list are refused", function()
		for _, key in { "Hello world", "", "Coins", nil, 5 } :: { any } do
			T.equal(PopupText.format(key, {}, Ui, limits, format), nil, tostring(key))
			T.equal((PopupText.check(key, {}, Ui, limits)), false, tostring(key))
		end
	end)

	test("missing, extra or invalid numbers are refused", function()
		T.equal((PopupText.check("PopupTestNumber", {}, Ui, limits)), false, "missing")
		T.equal((PopupText.check("PopupTest", { 1, 2, 3 }, Ui, limits)), false, "too many")
		for _, bad in { 0 / 0, math.huge, -math.huge, limits.MaxNumberMagnitude * 10, "5" } :: { any } do
			T.equal((PopupText.check("PopupTestNumber", { bad }, Ui, limits)), false, tostring(bad))
		end
	end)

	test("collect turns remote arguments into a list, refusing holes", function()
		T.equal(#(PopupText.collect() :: { any }), 0)
		T.equal(#(PopupText.collect(1, nil) :: { any }), 1)
		T.equal(#(PopupText.collect(1, 2) :: { any }), 2)
		T.equal(PopupText.collect(nil, 2), nil)
	end)

	test("the Popup remote: a bounded key and MaxNumbers optional bounded numbers", function()
		local definitions = Registry.build(declareRemotes(Schema, NetConfig, UpgradesConfig))
		local popup = definitions.Popup
		T.isTrue(popup ~= nil, "declared")
		T.equal(popup.kind, "Event")
		T.equal(popup.minArgs, 1)
		T.equal(popup.maxArgs, 1 + limits.MaxNumbers)
		T.equal(popup.rateLimit, NetConfig.RateLimits.Popup)
		T.equal((popup.args[1].check(string.rep("a", limits.MaxKeyLength + 1))), false, "long key")
		T.equal((popup.args[2].check(limits.MaxNumberMagnitude * 2)), false, "huge number")
		T.equal((popup.args[2].check(nil)), true, "numbers are optional")
	end)
end)

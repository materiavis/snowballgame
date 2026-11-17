--!strict
-- #90 Studio switches (ADR 0008): the HudTestPopup value parser, and source checks that every
-- #90 switch is bound only in Studio at PlaceId 0 and that the client never sends a pop-up.

local fs = require("@lune/fs")

local T = require("../../TestKit")
local PopupSwitch = require("../../../src/server/Services/HudTestService/PopupSwitch")

local STUDIO_GATE = "RunService:IsStudio() and game.PlaceId == 0"

return T.suite("HudTestService switches (#90)", function(test)
	test("a key alone, a key with numbers, spaces are trimmed", function()
		local key, numbers = PopupSwitch.parse("PopupTest")
		T.equal(key, "PopupTest")
		T.equal(#(numbers :: { number }), 0)
		key, numbers = PopupSwitch.parse(" PopupTestNumber , 3400 ")
		T.equal(key, "PopupTestNumber")
		T.equal((numbers :: { number })[1], 3400)
	end)

	test("empty keys, non-numbers and non-strings are refused with a reason", function()
		for _, value in { "", " ", ",5", "PopupTestNumber,abc", 5, true } :: { any } do
			local key, _, problem = PopupSwitch.parse(value)
			T.equal(key, nil, tostring(value))
			T.isTrue(type(problem) == "string", `reason for {tostring(value)}`)
		end
	end)

	test("the switch service and the client placeholder buttons are gated to Studio at PlaceId 0", function()
		for _, path in
			{
				"src/server/Services/HudTestService/init.luau",
				"src/places/simulator/client/SimulatorHudController/TestButtons.luau",
			}
		do
			local source = fs.readFile(path)
			T.isTrue(string.find(source, STUDIO_GATE, 1, true) ~= nil, `{path} checks {STUDIO_GATE}`)
		end
	end)

	test("no client code fires or handles the Popup remote towards the server", function()
		local source = fs.readFile("src/client/Controllers/PopupController.luau")
		for _, pattern in { "FireServer", "InvokeServer" } do
			T.equal(string.find(source, pattern, 1, true), nil, pattern)
		end
		local server = fs.readFile("src/server/Services/PopupService.luau")
		T.equal(string.find(server, "NetService.handle", 1, true), nil, "no server handler")
		T.equal(string.find(server, "OnServerEvent", 1, true), nil, "no server handler")
	end)
end)

--!strict
-- #90 left-edge registry (owner decision 2026-11-16): a button is hidden until its feature
-- registers it; any subset comes back in Config.Ui.LeftButtons order.

local T = require("../../TestKit")
local ButtonRegistry = require("../../../src/client/Ui/ButtonRegistry")
local Ui = require("../../../src/shared/Config/Ui") :: any

return T.suite("Ui ButtonRegistry (#90)", function(test)
	test("nothing is visible until registered", function()
		local registry = ButtonRegistry.new(Ui.LeftButtons)
		T.equal(#registry.visible(), 0)
		T.equal(registry.isRegistered("Pets"), false)
	end)

	test("every subset comes back in config order, whatever the registration order", function()
		local order = Ui.LeftButtons
		for mask = 0, 2 ^ #order - 1 do
			local registry = ButtonRegistry.new(order)
			local expected = {}
			-- Register in reverse so the order cannot come from the calls.
			for index = #order, 1, -1 do
				if bit32.btest(mask, 2 ^ (index - 1)) then
					registry.register(order[index])
				end
			end
			for index, id in order do
				if bit32.btest(mask, 2 ^ (index - 1)) then
					table.insert(expected, id)
				end
			end
			T.equal(table.concat(registry.visible(), ","), table.concat(expected, ","), `mask {mask}`)
		end
	end)

	test("unregister hides the button again; unregistering twice is harmless", function()
		local registry = ButtonRegistry.new(Ui.LeftButtons)
		registry.register("Lobby")
		T.equal(table.concat(registry.visible(), ","), "Lobby")
		T.equal(registry.unregister("Lobby"), true)
		T.equal(registry.unregister("Lobby"), false)
		T.equal(#registry.visible(), 0)
	end)

	test("unknown ids and double registrations fail loudly", function()
		local registry = ButtonRegistry.new(Ui.LeftButtons)
		T.throws(function()
			registry.register("Shop")
		end, "unknown button")
		registry.register("Pets")
		T.throws(function()
			registry.register("Pets")
		end, "registered twice")
	end)
end)

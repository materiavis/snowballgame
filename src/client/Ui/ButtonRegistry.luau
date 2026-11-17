--!strict
-- Which left-edge buttons are visible (concept 10.2, #90; owner decision 2026-11-16: a button
-- is hidden until its feature registers it). Pure: holds the registered ids and returns them
-- in the fixed order of Config.Ui.LeftButtons, so the HUD lays out any subset the same way.

export type ButtonRegistry = {
	register: (id: string) -> (),
	-- Returns true if the id was registered.
	unregister: (id: string) -> boolean,
	isRegistered: (id: string) -> boolean,
	isKnown: (id: string) -> boolean,
	-- Registered ids in config order.
	visible: () -> { string },
}

local ButtonRegistry = {}

function ButtonRegistry.new(order: { string }): ButtonRegistry
	local known: { [string]: boolean } = {}
	for _, id in order do
		known[id] = true
	end
	local registered: { [string]: boolean } = {}

	local registry = {}

	-- Errors on an id that is not in the order or is already registered, so wiring mistakes
	-- show at startup instead of as a missing or doubled button.
	function registry.register(id: string)
		if not known[id] then
			error(`ButtonRegistry: unknown button '{tostring(id)}' (add it to Config.Ui.LeftButtons)`, 2)
		end
		if registered[id] then
			error(`ButtonRegistry: button '{id}' registered twice`, 2)
		end
		registered[id] = true
	end

	function registry.unregister(id: string): boolean
		if not registered[id] then
			return false
		end
		registered[id] = nil
		return true
	end

	function registry.isRegistered(id: string): boolean
		return registered[id] == true
	end

	function registry.isKnown(id: string): boolean
		return known[id] == true
	end

	function registry.visible(): { string }
		local list = {}
		for _, id in order do
			if registered[id] then
				table.insert(list, id)
			end
		end
		return list
	end

	return table.freeze(registry) :: any
end

return table.freeze(ButtonRegistry)

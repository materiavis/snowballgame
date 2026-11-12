--!strict
-- Window stack (concept 10.2, ADR 0008). Pure: holds the order of open window ids and reports
-- every change through onChange, so MenuController only shows and hides frames.
-- Opening an open window moves it to the top. closeTop() closes the most recent one first.

export type OnChange = (id: string, isOpen: boolean) -> ()
export type WindowStack = {
	open: (id: string) -> boolean,
	close: (id: string) -> boolean,
	toggle: (id: string) -> boolean,
	closeTop: () -> string?,
	top: () -> string?,
	isOpen: (id: string) -> boolean,
	count: () -> number,
	list: () -> { string },
}

local WindowStack = {}

function WindowStack.new(onChange: OnChange?): WindowStack
	local order: { string } = {}

	local function notify(id: string, isOpen: boolean)
		if onChange then
			onChange(id, isOpen)
		end
	end

	local stack = {}

	-- Returns true if the window was not open before.
	function stack.open(id: string): boolean
		local index = table.find(order, id)
		if index then
			table.remove(order, index)
			table.insert(order, id)
			return false
		end
		table.insert(order, id)
		notify(id, true)
		return true
	end

	-- Returns true if the window was open.
	function stack.close(id: string): boolean
		local index = table.find(order, id)
		if not index then
			return false
		end
		table.remove(order, index)
		notify(id, false)
		return true
	end

	-- Returns the new state: true if the window is now open.
	function stack.toggle(id: string): boolean
		if table.find(order, id) then
			stack.close(id)
			return false
		end
		stack.open(id)
		return true
	end

	-- Returns the id that was closed, or nil if nothing was open.
	function stack.closeTop(): string?
		local id = order[#order]
		if id then
			stack.close(id)
		end
		return id
	end

	function stack.top(): string?
		return order[#order]
	end

	function stack.isOpen(id: string): boolean
		return table.find(order, id) ~= nil
	end

	function stack.count(): number
		return #order
	end

	function stack.list(): { string }
		return table.clone(order)
	end

	return table.freeze(stack) :: any
end

return table.freeze(WindowStack)

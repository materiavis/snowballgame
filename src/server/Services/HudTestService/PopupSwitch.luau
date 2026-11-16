--!strict
-- Parses the HudTestPopup switch value "<TextKey>[,<number>[,<number>]]" (#90, ADR 0008
-- "Studio switches"). Pure. Only splits and converts; PopupText.check decides whether the key
-- and the numbers are allowed.

local PopupSwitch = {}

-- Returns the key and the numbers, or nil and a reason.
function PopupSwitch.parse(value: any): (string?, { number }?, string?)
	if type(value) ~= "string" then
		return nil, nil, `expected "<TextKey>[,<number>,...]", got {typeof(value)}`
	end
	local parts = string.split(value, ",")
	local key = string.match(parts[1], "^%s*(.-)%s*$") :: string
	if key == "" then
		return nil, nil, "missing text key"
	end
	local numbers = {}
	for index = 2, #parts do
		local number = tonumber(string.match(parts[index], "^%s*(.-)%s*$"))
		if number == nil then
			return nil, nil, `part {index} is not a number: {parts[index]}`
		end
		table.insert(numbers, number)
	end
	return key, numbers, nil
end

return table.freeze(PopupSwitch)

--!strict
-- Pop-up text rules shared by PopupService (server) and PopupController (client), #90, ADR 0008.
-- Pure. A pop-up is a text key from Config.Ui.PopupTexts plus up to Config.Net.Popup.MaxNumbers
-- numbers; the text is Config.Ui.Text[key] with {1}, {2} replaced by the formatted numbers.
-- There is no free text: a key outside the list, a missing number for a placeholder or a
-- number out of bounds is refused.

local PopupText = {}

local function isAllowedKey(key: any, ui: any): boolean
	if type(key) ~= "string" or type(ui.Text[key]) ~= "string" then
		return false
	end
	return table.find(ui.PopupTexts, key) ~= nil
end

local function placeholders(template: string): number
	local highest = 0
	for digits in string.gmatch(template, "{(%d+)}") do
		highest = math.max(highest, tonumber(digits) :: number)
	end
	return highest
end

-- `numbers` is a list (may be empty). Returns ok, or false and a reason.
function PopupText.check(key: any, numbers: { any }, ui: any, limits: any): (boolean, string?)
	if not isAllowedKey(key, ui) then
		return false, `unknown pop-up text key {tostring(key)}`
	end
	if #numbers > limits.MaxNumbers then
		return false, `at most {limits.MaxNumbers} numbers`
	end
	for index, value in numbers do
		if type(value) ~= "number" or value ~= value or math.abs(value) > limits.MaxNumberMagnitude then
			return false, `number {index} is not a finite number within ±{limits.MaxNumberMagnitude}`
		end
	end
	local needed = placeholders(ui.Text[key])
	if needed > #numbers then
		return false, `text {key} needs {needed} numbers, got {#numbers}`
	end
	return true
end

-- The finished text, or nil when check() refuses. `formatNumber` is NumberFormat.number
-- (K, M, B ...). Negative numbers show with a minus sign.
function PopupText.format(key: any, numbers: { any }, ui: any, limits: any, formatNumber: (number) -> string): string?
	if not PopupText.check(key, numbers, ui, limits) then
		return nil
	end
	local ok, text = pcall(function(): string
		return (
			string.gsub(ui.Text[key], "{(%d+)}", function(digits: string): string
				local value = numbers[tonumber(digits) :: number] :: number
				if value < 0 then
					return "-" .. formatNumber(-value)
				end
				return formatNumber(value)
			end)
		)
	end)
	return if ok then text else nil
end

-- The number arguments of a remote call as a list. Trailing nils are dropped; a nil before a
-- number makes the call invalid (nil).
function PopupText.collect(...: any): { any }?
	local packed = table.pack(...)
	local last = 0
	for index = 1, packed.n do
		if packed[index] ~= nil then
			last = index
		end
	end
	local list = {}
	for index = 1, last do
		if packed[index] == nil then
			return nil
		end
		list[index] = packed[index]
	end
	return list
end

-- Whether a text key carries numbers (its label must not be auto-translated then, because a
-- changing value would make a new translation source every time).
function PopupText.hasNumbers(key: string, ui: any): boolean
	local template = ui.Text[key]
	return type(template) == "string" and placeholders(template) > 0
end

return table.freeze(PopupText)

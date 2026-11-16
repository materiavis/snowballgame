--!strict
-- What the HUD shows for a player's DataLoadStatus (ADR 0006, owner decision on #35).
-- Pure: the status comes only from the server's player attribute and this module never
-- guesses one. Balances show only while the status is "Loaded", otherwise Text.Missing
-- ("–"): never a stale value and never 0.

local LoadStatus = {}

function LoadStatus.isLoaded(status: any): boolean
	return status == "Loaded"
end

-- `format` is NumberFormat.number. A missing or invalid balance also shows Text.Missing.
function LoadStatus.balanceText(status: any, value: any, format: (number) -> string, ui: any): string
	if not LoadStatus.isLoaded(status) or type(value) ~= "number" then
		return ui.Text.Missing
	end
	local ok, text = pcall(format, value)
	if not ok then
		return ui.Text.Missing
	end
	return text
end

-- The hint text for a status, or nil for none. Unknown and missing statuses show no hint.
function LoadStatus.hint(status: any, ui: any): string?
	if type(status) ~= "string" then
		return nil
	end
	local key = ui.LoadHints[status]
	if key == nil then
		return nil
	end
	return ui.Text[key]
end

return table.freeze(LoadStatus)

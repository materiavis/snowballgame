--!strict
-- What the HUD's ball-size field shows (concept 7.4, 10.2; ADR 0008). Pure: the size and the MAX
-- flag come only from the server's player attributes (`BallSizeMetres`, `BallIsMax`, ADR 0002)
-- and this module never guesses one.

local BallSize = {}

-- `format` is NumberFormat.size (metres up to 999.9 m, then km). A missing or invalid size
-- shows Text.BallSizePlaceholder.
function BallSize.valueText(metres: any, format: (number) -> string, ui: any): string
	if type(metres) ~= "number" then
		return ui.Text.BallSizePlaceholder
	end
	local ok, text = pcall(format, metres)
	if not ok then
		return ui.Text.BallSizePlaceholder
	end
	return text
end

-- The caption and whether it uses the MAX colour. Only a real `true` counts as MAX.
function BallSize.caption(isMax: any, ui: any): (string, boolean)
	if isMax == true then
		return ui.Text.BallSizeMax, true
	end
	return ui.Text.BallSize, false
end

return table.freeze(BallSize)

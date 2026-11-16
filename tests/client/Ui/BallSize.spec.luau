--!strict
-- The HUD ball-size field (issue #35 point 3, concept 7.4 and 10.2): the size the server
-- published in BallSizeMetres, formatted by NumberFormat.size, "– m" until there is one, and the
-- interim "MAX!" caption while BallIsMax is true.

local T = require("../../TestKit")
local E = require("../../helpers/Economy")
local BallSize = require("../../../src/client/Ui/BallSize")
local Ui = require("../../../src/shared/Config/Ui") :: any

local format = E.NumberFormat.size

return T.suite("Ui BallSize (7.4)", function(test)
	test("a published size shows in metres, then in km from 1000 m", function()
		T.equal(BallSize.valueText(0.5, format, Ui), format(0.5))
		T.equal(BallSize.valueText(12.34, format, Ui), format(12.34))
		T.equal(BallSize.valueText(999.9, format, Ui), format(999.9))
		T.isTrue(string.find(BallSize.valueText(999.9, format, Ui), " m", 1, true) ~= nil, "999.9 is metres")
		T.isTrue(string.find(BallSize.valueText(1500, format, Ui), " km", 1, true) ~= nil, "1500 is km")
	end)

	test("no size yet, a non-number or a size the formatter refuses shows the placeholder", function()
		T.equal(BallSize.valueText(nil, format, Ui), Ui.Text.BallSizePlaceholder)
		T.equal(BallSize.valueText("12", format, Ui), Ui.Text.BallSizePlaceholder)
		T.equal(BallSize.valueText(-1, format, Ui), Ui.Text.BallSizePlaceholder)
		T.equal(BallSize.valueText(0 / 0, format, Ui), Ui.Text.BallSizePlaceholder)
		T.equal(BallSize.valueText(math.huge, format, Ui), Ui.Text.BallSizePlaceholder)
	end)

	test("the caption reads MAX! in the MAX colour only while BallIsMax is true", function()
		local text, max = BallSize.caption(true, Ui)
		T.equal(text, Ui.Text.BallSizeMax)
		T.equal(max, true)
		local none, noneMax = BallSize.caption(nil, Ui)
		T.equal(none, Ui.Text.BallSize)
		T.equal(noneMax, false)
		for _, value in { false, "true", 1 } :: { any } do
			local other, otherMax = BallSize.caption(value, Ui)
			T.equal(other, Ui.Text.BallSize)
			T.equal(otherMax, false)
		end
	end)
end)

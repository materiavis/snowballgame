--!strict
-- Load hint and balance text (issue #35 AC6, concept 6.5, owner decision 2026-11-06):
-- balances show only while DataLoadStatus is "Loaded", otherwise "–", never stale or 0.

local T = require("../../TestKit")
local E = require("../../helpers/Economy")
local LoadStatus = require("../../../src/client/Ui/LoadStatus")
local Ui = require("../../../src/shared/Config/Ui") :: any

local format = E.NumberFormat.number
local STATUSES = { "Loading", "Loaded", "Failed", "Lost", "Teleported", "Released" }

local function assertDeepFrozen(value: any, path: string)
	if type(value) ~= "table" then
		return
	end
	T.isTrue(table.isfrozen(value), `{path} is frozen`)
	for key, inner in value do
		assertDeepFrozen(inner, `{path}.{tostring(key)}`)
	end
end

return T.suite("Ui LoadStatus (6.5)", function(test)
	test("Config.Ui is frozen all the way down", function()
		assertDeepFrozen(Ui, "Ui")
	end)

	test("Loaded shows the formatted balance, including a real 0", function()
		T.equal(LoadStatus.balanceText("Loaded", 3400, format, Ui), "3.4K")
		T.equal(LoadStatus.balanceText("Loaded", 0, format, Ui), "0")
		T.equal(LoadStatus.balanceText("Loaded", 3755901, format, Ui), "3.7M")
	end)

	test("every other status shows the missing mark, whatever the stale attribute says", function()
		for _, status in STATUSES do
			if status ~= "Loaded" then
				T.equal(LoadStatus.balanceText(status, 12345, format, Ui), Ui.Text.Missing, status)
				T.equal(LoadStatus.balanceText(status, 0, format, Ui), Ui.Text.Missing, `{status} with 0`)
			end
		end
		T.equal(Ui.Text.Missing, "–")
	end)

	test("no status yet, an unknown status or a bad balance shows the missing mark", function()
		T.equal(LoadStatus.balanceText(nil, 50, format, Ui), Ui.Text.Missing)
		T.equal(LoadStatus.balanceText("loaded", 50, format, Ui), Ui.Text.Missing)
		T.equal(LoadStatus.balanceText("Loaded", nil, format, Ui), Ui.Text.Missing)
		T.equal(LoadStatus.balanceText("Loaded", "50", format, Ui), Ui.Text.Missing)
		T.equal(LoadStatus.balanceText("Loaded", 0 / 0, format, Ui), Ui.Text.Missing)
	end)

	test("the hint shows for Failed only; Loading shows no hint", function()
		T.equal(LoadStatus.hint("Failed", Ui), Ui.Text.LoadFailed)
		T.isTrue(type(Ui.Text.LoadFailed) == "string" and #Ui.Text.LoadFailed > 0)
		for _, status in STATUSES do
			if status ~= "Failed" then
				T.equal(LoadStatus.hint(status, Ui), nil, status)
			end
		end
		T.equal(LoadStatus.hint(nil, Ui), nil)
	end)

	test("every hint key points at a text", function()
		for status, key in Ui.LoadHints do
			T.isTrue(type(Ui.Text[key]) == "string", `{status} -> {key}`)
		end
	end)
end)

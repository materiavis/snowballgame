--!strict
-- Studio: a require of DataService from the command bar or a plugin (e.g. the playtest tool's
-- execute_luau) can get its own copy of the module. If that copy set up too, it would load the
-- players into its own fake store, take DataSimulateRejoin away from the game's copy and overwrite
-- DataLoadStatus (#37 round 1 playtest). The Roblox wiring in init.luau cannot load under Lune,
-- so the guard is checked as text.

local T = require("../../TestKit")
local SourceSection = require("../../helpers/SourceSection")

local DATA_SERVICE = "src/server/Services/DataService/init.luau"

return T.suite("DataService second module copy in Studio (ADR 0006)", function(test)
	test("a later copy refuses to own the server", function()
		local claim = SourceSection.between(DATA_SERVICE, "local function claimInstance()", "local function setUp()")
		T.isTrue(SourceSection.at(claim, "owner ~= nil and owner ~= instanceToken") ~= nil, "refuses a second owner")
		T.isTrue(SourceSection.at(claim, "return false") ~= nil)
	end)

	test("the guard is Studio-only and runs before any session or switch is set up", function()
		local setUp = SourceSection.between(DATA_SERVICE, "local function setUp()", "function DataService.Start()")
		local guard = SourceSection.at(setUp, "if isStudio and not claimInstance() then\n\t\treturn")
		T.isTrue(guard ~= nil, "Studio-only guard in setUp")
		for _, later in
			{
				"core.subscribe(",
				"GetAttributeChangedSignal(SIMULATE_REJOIN_ATTRIBUTE)",
				"Players.PlayerAdded:Connect(onPlayerAdded)",
			}
		do
			local at = SourceSection.at(setUp, later)
			T.isTrue(at ~= nil and (guard :: number) < at, `{later} only after the guard`)
		end
	end)
end)

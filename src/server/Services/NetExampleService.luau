--!strict
-- EXAMPLE ONLY, not gameplay. Handles the NetExample remote so a playtest can see a valid
-- call reach its handler, and shows the NetService.handle pattern real services follow.
-- Delete together with the NetExample declaration once the first real remote exists.

local RunService = game:GetService("RunService")

local NetService = require(script.Parent:WaitForChild("NetService"))

local NetExampleService = {}

local handled = 0

function NetExampleService.Start()
	NetService.handle("NetExample", function(player: Player, amount: number, values: { number })
		handled += 1
		-- Studio only, read by the playtest. The guard already proved amount and values are in range.
		if RunService:IsStudio() then
			local remote = NetService.getRemote("NetExample")
			remote:SetAttribute("ExampleHandled", handled)
			remote:SetAttribute("ExampleLastCall", `{player.Name}: {amount}, {#values} values`)
		end
	end)
end

return NetExampleService

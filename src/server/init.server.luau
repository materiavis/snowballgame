--!strict
-- Server entry point. Requires and starts every service in ./Services.

local Services = script:WaitForChild("Services")

for _, module in Services:GetChildren() do
	if module:IsA("ModuleScript") then
		local service = require(module) :: any
		if type(service) == "table" and type(service.Start) == "function" then
			task.spawn(service.Start)
		end
	end
end

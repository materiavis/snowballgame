--!strict
-- Client entry point. Requires and starts every controller in ./Controllers.

local Controllers = script:WaitForChild("Controllers")

for _, module in Controllers:GetChildren() do
	if module:IsA("ModuleScript") then
		local controller = require(module) :: any
		if type(controller) == "table" and type(controller.Start) == "function" then
			task.spawn(controller.Start)
		end
	end
end

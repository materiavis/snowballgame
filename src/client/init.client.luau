--!strict
-- Client entry point. Starts the core controllers, then the folders this Place's Rojo project mounts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceInfo = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlaceInfo"))

local function startModules(folder: Instance): number
	local started = 0
	for _, module in folder:GetChildren() do
		if module:IsA("ModuleScript") then
			local controller = require(module) :: any
			if type(controller) == "table" and type(controller.Start) == "function" then
				task.spawn(controller.Start)
				started += 1
			end
		end
	end
	return started
end

-- This script's children may arrive after it starts, so FindFirstChild could silently skip a folder.
-- Which folders to wait for comes from the role, because waiting for an unmounted one would never end.
local started = startModules(script:WaitForChild("Controllers"))
if PlaceInfo.UsesSocial then
	started += startModules(script:WaitForChild("SocialControllers"))
end
started += startModules(script:WaitForChild("PlaceControllers"))

print(`[Client] PlaceRole={PlaceInfo.Role} started {started} controllers`)

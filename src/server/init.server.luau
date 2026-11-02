--!strict
-- Server entry point. Starts the core services, then the folders this Place's Rojo project mounts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceInfo = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlaceInfo"))

local function startModules(folder: Instance): number
	local started = 0
	for _, module in folder:GetChildren() do
		if module:IsA("ModuleScript") then
			local service = require(module) :: any
			if type(service) == "table" and type(service.Start) == "function" then
				task.spawn(service.Start)
				started += 1
			end
		end
	end
	return started
end

local started = startModules(script:WaitForChild("Services"))
if PlaceInfo.UsesSocial then
	started += startModules(script:WaitForChild("SocialServices"))
end
started += startModules(script:WaitForChild("PlaceServices"))

print(`[Server] PlaceRole={PlaceInfo.Role} started {started} services`)

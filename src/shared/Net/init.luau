--!strict
-- Net: the one registry of remotes, shared by server and client.
-- Requiring it builds and checks every declaration in Remotes, so a remote without a
-- schema or rate limit stops the server (and client) at startup.
--
-- Server code registers handlers through NetService.handle; client code gets the instance
-- through Net.waitForRemote. Neither creates or connects remotes directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetConfig = require(script.Parent:WaitForChild("Config"):WaitForChild("Net"))
local Registry = require(script:WaitForChild("Registry"))
local Schema = require(script:WaitForChild("Schema"))
local declareRemotes = require(script:WaitForChild("Remotes"))

local Net = {
	FOLDER_NAME = "Remotes",
	Schema = Schema,
	Definitions = Registry.build(declareRemotes(Schema, NetConfig)),
}

function Net.isDeclared(name: string): boolean
	return Net.Definitions[name] ~= nil
end

-- Client-side access. Errors on an undeclared name so a typo does not wait forever.
function Net.waitForRemote(name: string): Instance
	if not Net.isDeclared(name) then
		error(`Net: remote '{name}' is not declared in Net/Remotes`, 2)
	end
	return ReplicatedStorage:WaitForChild(Net.FOLDER_NAME):WaitForChild(name)
end

return table.freeze(Net)

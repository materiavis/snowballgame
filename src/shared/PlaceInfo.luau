--!strict
-- Tells a script which Place it runs in, from the Workspace attributes set by each Place's Rojo project.
-- A guessed default would silently start the wrong services, so anything unexpected is an error.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type PlaceRole = "Lobby" | "Simulator" | "Arena"

local ROLE_USES_SOCIAL: { [string]: boolean } = {
	Lobby = true,
	Simulator = true,
	Arena = false,
}

-- Client scripts can run before the initial replication has delivered Workspace's attributes.
if RunService:IsClient() and not game:IsLoaded() then
	game.Loaded:Wait()
end

local role = Workspace:GetAttribute("PlaceRole")
if type(role) ~= "string" or ROLE_USES_SOCIAL[role] == nil then
	error(`PlaceInfo: Workspace attribute PlaceRole is missing or unknown: {role}`, 0)
end

local worldIndex = Workspace:GetAttribute("WorldIndex")
if role == "Simulator" then
	if type(worldIndex) ~= "number" or worldIndex < 1 or worldIndex % 1 ~= 0 then
		error(`PlaceInfo: Simulator needs a positive whole WorldIndex attribute, got: {worldIndex}`, 0)
	end
elseif worldIndex ~= nil then
	error(`PlaceInfo: WorldIndex is only valid in a Simulator Place, but PlaceRole is {role}`, 0)
end

local PlaceInfo = {
	Role = role :: PlaceRole,
	WorldIndex = worldIndex :: number?,
	UsesSocial = ROLE_USES_SOCIAL[role],
}

return table.freeze(PlaceInfo)

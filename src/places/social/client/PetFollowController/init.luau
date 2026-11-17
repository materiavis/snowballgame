--!strict
-- Equipped pets follow their player (concept 7.9 "Mitlaufen", ADR 0003 R2, ADR 0013). Client-only
-- rendering: the server publishes each player's equipped pets as the attribute `PetEquipped`
-- (PetCodec); every client draws them. Nothing is sent to the server.
--
-- Runs only where Config.Pets.Follow.Roles allows (Simulator now; Lobby with #103). The Arena
-- does not mount this folder, so no pets follow there (decision 15.10).
--
-- Own pets: detailed (body, head, name label), every frame, with a small bob. Pets of other
-- players (R2): one part, no label, no bob, Config.Pets.Follow.ForeignUpdateRate times a second,
-- hidden beyond ForeignMaxDistance. Placeholder shapes until pet models exist.
--
-- Studio at PlaceId 0: the player attribute PetFollowForeignPreview (PetService switch) also
-- draws the local player's own pets through the foreign path, so R2 can be checked alone.
-- Playtest handles: Workspace.ClientPets.<UserId>[Preview].<uid> Models (attributes Kind,
-- Owner, Simplified); each player folder carries UpdateRate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets")) :: any
local PetCatalogue = require(Shared:WaitForChild("PetCatalogue")) :: any
local PetCodec = require(Shared:WaitForChild("PetCodec"))
local PlaceInfo = require(Shared:WaitForChild("PlaceInfo"))
local Rarity = require(Shared:WaitForChild("Rarity")) :: any

local PetFormation = require(script:WaitForChild("PetFormation"))
local PetModels = require(script:WaitForChild("PetModels"))

local FOLDER = "ClientPets"
local PREVIEW_ATTRIBUTE = "PetFollowForeignPreview"
-- The preview group stands beside the own group, so both are visible at once.
local PREVIEW_SIDE_OFFSET = 8

type Pet = { uid: string, visual: any, cframe: CFrame? }
type Group = {
	owner: Player,
	simplified: boolean,
	side: number,
	folder: Folder,
	pets: { Pet },
	accumulated: number,
}

local PetFollowController = {}

local follow = PetsConfig.Follow

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") then
		return root, humanoid
	end
	return nil, nil
end

function PetFollowController.Start()
	if not follow.Roles[PlaceInfo.Role] then
		print(`[PetFollowController] no following pets in {PlaceInfo.Role}`)
		return
	end
	local localPlayer = Players.LocalPlayer
	local studio = RunService:IsStudio() and game.PlaceId == 0
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = Workspace

	local groups: { [string]: Group } = {}

	local function sync(group: Group)
		local wanted = PetCodec.decodeEquipped(group.owner:GetAttribute(PetsConfig.Attributes.Equipped))
		local existing: { [string]: Pet } = {}
		for _, pet in group.pets do
			existing[pet.uid] = pet
		end
		local list: { Pet } = {}
		for _, entry in wanted do
			local info = PetCatalogue.get(entry.kind)
			if info then
				local pet = existing[entry.uid]
				if pet then
					existing[entry.uid] = nil
				else
					local colour = Rarity.color3(info.rarity)
					local visual = PetModels.create({
						uid = entry.uid,
						kind = entry.kind,
						owner = group.owner.UserId,
						simplified = group.simplified,
						colour = colour,
						labelText = if group.simplified then nil else `{info.name} {Rarity.get(info.rarity).symbol}`,
						follow = follow,
					})
					visual.model.Parent = group.folder
					pet = { uid = entry.uid, visual = visual, cframe = nil }
				end
				table.insert(list, pet)
			end
		end
		for _, pet in existing do
			pet.visual.model:Destroy()
		end
		group.pets = list
	end

	local function addGroup(player: Player, key: string, simplified: boolean, side: number)
		if groups[key] then
			return
		end
		local groupFolder = Instance.new("Folder")
		groupFolder.Name = key
		groupFolder:SetAttribute("UpdateRate", if simplified then follow.ForeignUpdateRate else 0)
		groupFolder.Parent = folder
		local group: Group = {
			owner = player,
			simplified = simplified,
			side = side,
			folder = groupFolder,
			pets = {},
			accumulated = 0,
		}
		groups[key] = group
		sync(group)
	end

	local function removeGroup(key: string)
		local group = groups[key]
		if group then
			groups[key] = nil
			group.folder:Destroy()
		end
	end

	local function updatePreview()
		local key = `{localPlayer.UserId}Preview`
		if studio and localPlayer:GetAttribute(PREVIEW_ATTRIBUTE) == true then
			addGroup(localPlayer, key, true, PREVIEW_SIDE_OFFSET)
		else
			removeGroup(key)
		end
	end

	local function watch(player: Player)
		local own = player == localPlayer
		addGroup(player, tostring(player.UserId), not own, 0)
		player:GetAttributeChangedSignal(PetsConfig.Attributes.Equipped):Connect(function()
			for _, group in groups do
				if group.owner == player then
					sync(group)
				end
			end
		end)
		if own then
			player:GetAttributeChangedSignal(PREVIEW_ATTRIBUTE):Connect(updatePreview)
			updatePreview()
		end
	end

	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		for key, group in groups do
			if group.owner == player then
				removeGroup(key)
			end
		end
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}

	local function step(group: Group, dt: number, now: number, viewer: Vector3?)
		local root, humanoid = rootOf(group.owner)
		if root == nil then
			return
		end
		local hidden = group.simplified
			and viewer ~= nil
			and (root.Position - viewer).Magnitude > follow.ForeignMaxDistance
		local count = #group.pets
		local alpha = PetFormation.alpha(dt, follow.Sharpness)
		-- Level with the ground: only the character's heading counts, not its tilt.
		local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local facing = if flat.Magnitude > 1e-3
			then CFrame.lookAt(root.Position, root.Position + flat.Unit)
			else CFrame.new(root.Position)
		for index, pet in group.pets do
			local visual = pet.visual
			if hidden then
				visual.model.Parent = nil
				continue
			end
			visual.model.Parent = group.folder
			local x, z = PetFormation.offset(index, count, follow)
			local y = PetFormation.height(
				root.Position.Y,
				root.Size.Y / 2,
				if humanoid then humanoid.HipHeight else 0,
				visual.size
			)
			if not group.simplified then
				y += follow.BobHeight * math.sin(now * follow.BobSpeed + index)
			end
			local target = facing * CFrame.new(x + group.side, 0, z)
			target = CFrame.new(target.Position.X, y, target.Position.Z) * facing.Rotation
			local current = pet.cframe
			if current == nil or PetFormation.shouldSnap((current.Position - target.Position).Magnitude, follow) then
				current = target
			else
				current = current:Lerp(target, alpha)
			end
			pet.cframe = current
			for partIndex, part in visual.parts do
				table.insert(parts, part)
				table.insert(cframes, current * visual.offsets[partIndex])
			end
		end
	end

	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		local viewerRoot = rootOf(localPlayer)
		local viewer = if viewerRoot then viewerRoot.Position else nil
		table.clear(parts)
		table.clear(cframes)
		for _, group in groups do
			if group.simplified then
				group.accumulated += dt
				if group.accumulated >= 1 / follow.ForeignUpdateRate then
					step(group, group.accumulated, now, viewer)
					group.accumulated = 0
				end
			else
				step(group, dt, now, viewer)
			end
		end
		if #parts > 0 then
			-- One engine call for every pet part; the parts are anchored and client-only.
			Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return PetFollowController

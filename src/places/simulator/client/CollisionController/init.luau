--!strict
-- CollisionController (Simulator only, ADR 0003 rev. 2 "Ball collisions with foreign
-- characters", extended in ADR 0002): assigns the global collision groups locally, from this
-- client's view.
--   own character parts (also after respawn and parts added later) -> OwnCharacter
--   every other character's parts (join, respawn, added or streamed in later) -> OtherCharacters
--   own ball -> OwnBall, every other ball -> Balls
-- BallService registers the groups and rules once on the server; they replicate. Local
-- CollisionGroup changes do not replicate, so the server keeps its own view (balls in Balls,
-- characters in Default). No part gets CanCollide = false; only the group pairs decide.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any
local CollisionAssign = require(script:WaitForChild("CollisionAssign"))

-- Local player attributes (playtest hooks; client-side only).
local RULES_OK_ATTRIBUTE = "CollisionRulesOk"
local CHARACTER_PARTS_ATTRIBUTE = "CollisionOwnCharacterParts"
local FOREIGN_CHARACTER_PARTS_ATTRIBUTE = "CollisionForeignCharacterParts"
local OWN_BALL_ATTRIBUTE = "CollisionOwnBallGroup"
local FOREIGN_BALLS_ATTRIBUTE = "CollisionForeignBalls"

local localPlayer = Players.LocalPlayer
local groups = BallConfig.CollisionGroups

local CollisionController = {}

type Tracked = { player: Player, group: string, connections: { RBXScriptConnection } }

local ballsFolder: Instance? = nil
local tracked: { [Model]: Tracked } = {}
local countsQueued = false
local started = false

local function groupsRegistered(): boolean
	for _, name in groups do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			return false
		end
	end
	return true
end

local function checkRules(): (boolean, string)
	local ok = true
	local parts: { string } = {}
	for _, rule in BallConfig.CollisionRules do
		local actual = PhysicsService:CollisionGroupsAreCollidable(rule[1], rule[2])
		if actual ~= rule[3] then
			ok = false
		end
		table.insert(parts, `{rule[1]}<->{rule[2]}={actual}`)
	end
	return ok, table.concat(parts, " ")
end

local function setGroup(part: Instance, group: string)
	if part:IsA("BasePart") and part.CollisionGroup ~= group then
		part.CollisionGroup = group
	end
end

local function countParts(character: Model, group: string): number
	local count = 0
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.CollisionGroup == group then
			count += 1
		end
	end
	return count
end

-- Counting once per frame at most: a spawning character adds its parts one by one.
local function queueCounts()
	if countsQueued then
		return
	end
	countsQueued = true
	task.defer(function()
		countsQueued = false
		local own, foreign = 0, 0
		for character, info in tracked do
			local count = countParts(character, info.group)
			if info.player == localPlayer then
				own += count
			else
				foreign += count
			end
		end
		localPlayer:SetAttribute(CHARACTER_PARTS_ATTRIBUTE, own)
		localPlayer:SetAttribute(FOREIGN_CHARACTER_PARTS_ATTRIBUTE, foreign)
	end)
end

local function untrackCharacter(character: Model)
	local info = tracked[character]
	if info then
		tracked[character] = nil
		for _, connection in info.connections do
			connection:Disconnect()
		end
		queueCounts()
	end
end

local function trackCharacter(player: Player, character: Model)
	local group = CollisionAssign.groupForCharacter(player.UserId, localPlayer.UserId, groups)
	for _, descendant in character:GetDescendants() do
		setGroup(descendant, group)
	end
	if not tracked[character] then
		tracked[character] = {
			player = player,
			group = group,
			connections = {
				-- Accessories, tools and parts that arrive later or stream in.
				character.DescendantAdded:Connect(function(descendant)
					setGroup(descendant, group)
					queueCounts()
				end),
				character.Destroying:Connect(function()
					untrackCharacter(character)
				end),
			},
		}
		print(`[CollisionController] character {player.Name} parts={countParts(character, group)} -> {group}`)
	end
	queueCounts()
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		trackCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(untrackCharacter)
	if player.Character then
		trackCharacter(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	for character, info in tracked do
		if info.player == player then
			untrackCharacter(character)
		end
	end
end

local function publishBalls()
	local folder = ballsFolder
	if not folder then
		return
	end
	local foreign = 0
	local own = "none"
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			if child:GetAttribute(BallConfig.OwnerAttribute) == localPlayer.UserId then
				own = child.CollisionGroup
			elseif child.CollisionGroup == groups.Balls then
				foreign += 1
			end
		end
	end
	localPlayer:SetAttribute(OWN_BALL_ATTRIBUTE, own)
	localPlayer:SetAttribute(FOREIGN_BALLS_ATTRIBUTE, foreign)
end

-- Runs for every ball that arrives, including foreign balls streaming in again.
local function onBallAdded(child: Instance)
	if not child:IsA("BasePart") then
		return
	end
	local group =
		CollisionAssign.groupForBall(child:GetAttribute(BallConfig.OwnerAttribute), localPlayer.UserId, groups)
	setGroup(child, group)
	publishBalls()
end

function CollisionController.Start()
	if started then
		return
	end
	started = true

	-- The server registers the groups at start; replication can lag behind this script.
	while not groupsRegistered() do
		task.wait()
	end
	local rulesOk, rulesText = checkRules()
	localPlayer:SetAttribute(RULES_OK_ATTRIBUTE, rulesOk)
	if not rulesOk then
		warn(`[CollisionController] collision rules do not hold: {rulesText}`)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	-- A character model that streams back in arrives as a new child of Workspace without a
	-- new CharacterAdded.
	workspace.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(child)
			if player then
				trackCharacter(player, child)
			end
		end
	end)

	local folder = workspace:WaitForChild(BallConfig.FolderName)
	ballsFolder = folder
	folder.ChildAdded:Connect(onBallAdded)
	folder.ChildRemoved:Connect(function()
		publishBalls()
	end)
	for _, child in folder:GetChildren() do
		onBallAdded(child)
	end
	publishBalls()

	print(`[CollisionController] started rules={if rulesOk then "ok" else "FAILED"} {rulesText}`)
end

return CollisionController

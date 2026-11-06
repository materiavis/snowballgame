--!strict
-- CollisionController (Simulator only, ADR 0003 rev. 2 "Ball collisions with foreign
-- characters"): assigns the global ball collision groups locally, from this client's view.
--   own character parts (also after respawn and parts added later) -> OwnCharacter
--   own ball -> OwnBall, every other ball -> Balls
-- BallService registers the groups and rules once on the server; they replicate. Local
-- CollisionGroup changes do not replicate, so the server keeps its own view (balls in Balls,
-- characters in Default). Foreign balls keep CanCollide; only the group pairs decide.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any
local CollisionAssign = require(script:WaitForChild("CollisionAssign"))

-- Local player attributes (playtest hooks; client-side only).
local RULES_OK_ATTRIBUTE = "CollisionRulesOk"
local CHARACTER_PARTS_ATTRIBUTE = "CollisionOwnCharacterParts"
local OWN_BALL_ATTRIBUTE = "CollisionOwnBallGroup"
local FOREIGN_BALLS_ATTRIBUTE = "CollisionForeignBalls"

local localPlayer = Players.LocalPlayer
local groups = BallConfig.CollisionGroups

local CollisionController = {}

local ballsFolder: Instance? = nil
local characterConnection: RBXScriptConnection? = nil
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

local function countCharacterParts(character: Model): number
	local count = 0
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.CollisionGroup == groups.OwnCharacter then
			count += 1
		end
	end
	return count
end

local function onCharacter(character: Model)
	if characterConnection then
		characterConnection:Disconnect()
	end
	for _, descendant in character:GetDescendants() do
		setGroup(descendant, groups.OwnCharacter)
	end
	-- Accessories, tools and parts the character builds after spawning.
	characterConnection = character.DescendantAdded:Connect(function(descendant)
		setGroup(descendant, groups.OwnCharacter)
		localPlayer:SetAttribute(CHARACTER_PARTS_ATTRIBUTE, countCharacterParts(character))
	end)
	local count = countCharacterParts(character)
	localPlayer:SetAttribute(CHARACTER_PARTS_ATTRIBUTE, count)
	print(`[CollisionController] character parts={count} -> {groups.OwnCharacter}`)
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

	localPlayer.CharacterAdded:Connect(onCharacter)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end

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

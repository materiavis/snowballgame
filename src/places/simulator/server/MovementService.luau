--!strict
-- MovementService (Simulator only, concept 7.3): base walk speed and no jumping.
-- The ball moves at the character's speed (BallController), so push speed follows
-- Humanoid.WalkSpeed. The Walk speed upgrade (#36) and the "Schnelle Schuhe" pass (#60) only
-- change the WalkSpeed this service sets; they are not part of this module yet.
--
-- JumpPower and JumpHeight 0 also hide the mobile jump button (the default touch controls
-- show it only while the humanoid can jump). MovementController turns off the Jumping state
-- on the client, which simulates its own character. Lobby and Arena keep Roblox defaults.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any

local MovementService = {}

local started = false

local function applyMovement(humanoid: Humanoid)
	humanoid.WalkSpeed = BallConfig.WalkSpeed
	if not BallConfig.JumpEnabled then
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		applyMovement(humanoid)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

function MovementService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	print(`[MovementService] started walkSpeed={BallConfig.WalkSpeed} jumpEnabled={BallConfig.JumpEnabled}`)
end

return MovementService

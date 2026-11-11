--!strict
-- MovementController (Simulator only, concept 7.3): no jumping. This client simulates its own
-- character, so the Jumping state is turned off here; MovementService sets JumpPower and
-- JumpHeight to 0 on the server, which also hides the mobile jump button. Walk speed comes
-- from the server only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ball")) :: any

local localPlayer = Players.LocalPlayer

local MovementController = {}

local started = false

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") and not BallConfig.JumpEnabled then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
end

function MovementController.Start()
	if started then
		return
	end
	started = true
	localPlayer.CharacterAdded:Connect(onCharacter)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	print(`[MovementController] started jumpEnabled={BallConfig.JumpEnabled}`)
end

return MovementController

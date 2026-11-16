--!strict
-- MovementService (Simulator only, concept 7.3, 7.8): walk speed and no jumping. The only writer
-- of Humanoid.WalkSpeed in the Simulator.
-- The ball moves at the character's speed (BallController), so push speed follows
-- Humanoid.WalkSpeed. Walk speed is the Walk speed upgrade's effect (UpgradeService, #36): set on
-- every spawn and again whenever the level changes, so a purchase is felt at once. The
-- "Schnelle Schuhe" pass (#60) will change the value computed here; it is not part of it yet.
--
-- JumpPower and JumpHeight 0 also hide the mobile jump button (the default touch controls
-- show it only while the humanoid can jump). MovementController turns off the Jumping state
-- on the client, which simulates its own character. Lobby and Arena keep Roblox defaults.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ball")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))

local WALK_SPEED_UPGRADE = "walkSpeed"

local MovementService = {}

local started = false

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function applyWalkSpeed(player: Player, humanoid: Humanoid)
	humanoid.WalkSpeed = UpgradeService.GetEffect(player, WALK_SPEED_UPGRADE)
end

local function applyMovement(player: Player, humanoid: Humanoid)
	applyWalkSpeed(player, humanoid)
	if not BallConfig.JumpEnabled then
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		applyMovement(player, humanoid)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

function MovementService.Start()
	if started then
		return
	end
	started = true

	-- Growth is calibrated at Config.Ball.WalkSpeed (GrowthRules), so the unupgraded walk speed
	-- must be the same number.
	local base = Formulas.Upgrades.effect(WALK_SPEED_UPGRADE, 0)
	if base ~= BallConfig.WalkSpeed then
		warn(`[MovementService] walkSpeed upgrade level 0 is {base}, Config.Ball.WalkSpeed is {BallConfig.WalkSpeed}`)
	end

	UpgradeService.LevelChanged:Connect(function(player: Player, id: string)
		if id ~= WALK_SPEED_UPGRADE then
			return
		end
		local humanoid = humanoidOf(player)
		if humanoid then
			applyWalkSpeed(player, humanoid)
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	print(`[MovementService] started walkSpeed={base} (Walk speed upgrade) jumpEnabled={BallConfig.JumpEnabled}`)
end

return MovementService

--!strict
-- FindController (Simulator only, concept 7.7, 8.5, ADR 0016): shows this player's own finds.
-- Display only: the server spawns, rolls and picks up, and tells this client on FindUpdate.
-- Nothing here is sent back.
--
-- * Spawned finds: a placeholder at the point (a disc in the rarity colour with its stars or
--   crown under it, never colour alone), drawn as a BillboardGui on an Attachment in Terrain.
--   No part is created, so nothing local can collide with a character or a ball.
-- * Finds in the own ball: the same placeholder on Attachments inside the ball part, spread over
--   its surface and resized with the ball, until the server says the ball was sold.
-- * Secret find ball effect: Sparkles (built in, no asset) on every ball whose owner has the
--   server-written Config.Finds.BallEffectAttribute.
-- Other players' finds stuck in their balls are not drawn (ADR 0003 R2).
-- Read-only playtest handles on the LocalPlayer: FindClientVisible, FindClientInBall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BallConfig = require(Config:WaitForChild("Ball")) :: any
local FindsConfig = require(Config:WaitForChild("Finds")) :: any
local NetConfig = require(Config:WaitForChild("Net")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Rarity = require(Shared:WaitForChild("Rarity")) :: any

local FindView = require(script:WaitForChild("FindView"))

local REMOTE = "FindUpdate"
local SECRET = "Secret"

local Visual = FindsConfig.Visual
local names = FindsConfig.DiagnosticAttributes

local FindController = {}

local started = false
local player = Players.LocalPlayer

type Shown = { attachment: Attachment, findId: string }
local spawned: { [number]: Shown } = {}
local ballFinds: { string } = {}
local inBall: { Attachment } = {}
local ownBall: BasePart? = nil
local ballSizeConnection: RBXScriptConnection? = nil

local function publish()
	local count = 0
	for _ in spawned do
		count += 1
	end
	player:SetAttribute(names.ClientVisible, count)
	player:SetAttribute(names.ClientInBall, #inBall)
end

local function billboard(findId: string, size: number, parent: Instance, slot: number?): BillboardGui
	local item = FindsConfig.Items[findId]
	local info = Rarity.get(item.Rarity)
	local colour = Rarity.color3(item.Rarity)
	local height = FindView.billboardHeight(Visual, size)

	local gui = Instance.new("BillboardGui")
	gui.Name = "FindBillboard"
	gui.Size = UDim2.fromScale(size, height)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = Visual.MaxDistance
	gui:SetAttribute("FindId", findId)
	gui:SetAttribute("Rarity", item.Rarity)
	gui:SetAttribute("Slot", slot)

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.Size = UDim2.fromScale(1, 1 - Visual.SymbolHeightShare)
	disc.BackgroundColor3 = colour
	disc.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(Visual.CornerShare, 0)
	corner.Parent = disc
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = Visual.StrokeThickness
	stroke.Parent = disc
	disc.Parent = gui

	local symbol = Instance.new("TextLabel")
	symbol.Name = "Symbol"
	symbol.AutoLocalize = false
	symbol.BackgroundTransparency = 1
	symbol.Position = UDim2.fromScale(0, 1 - Visual.SymbolHeightShare)
	symbol.Size = UDim2.fromScale(1, Visual.SymbolHeightShare)
	symbol.Text = info.symbol
	symbol.TextScaled = true
	symbol.TextColor3 = colour
	symbol.TextStrokeTransparency = 0
	symbol.Parent = gui

	gui.Parent = parent
	return gui
end

local function removeSpawned(slot: number)
	local shown = spawned[slot]
	if shown then
		spawned[slot] = nil
		shown.attachment:Destroy()
	end
end

local function showSpawned(slot: number, findId: string, position: Vector3)
	removeSpawned(slot)
	local attachment = Instance.new("Attachment")
	attachment.Name = `Find_{slot}`
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = position + Vector3.new(0, Visual.HeightAboveGround, 0)
	attachment:SetAttribute("FindId", findId)
	attachment:SetAttribute("Point", position)
	billboard(findId, Visual.SizeStuds, attachment, slot)
	spawned[slot] = { attachment = attachment, findId = findId }
end

local function placeInBall()
	local ball = ownBall
	if ball == nil then
		return
	end
	local diameter = ball.Size.X
	local size = FindView.inBallSize(Visual, diameter)
	for index, attachment in inBall do
		local direction = FindView.inBallDirection(index, Visual.MaxInBall)
		attachment.Position = Vector3.new(direction.x, direction.y, direction.z) * (diameter / 2)
		local gui = attachment:FindFirstChildOfClass("BillboardGui")
		if gui then
			gui.Size = UDim2.fromScale(size, FindView.billboardHeight(Visual, size))
		end
	end
end

local function rebuildBall()
	for _, attachment in inBall do
		attachment:Destroy()
	end
	inBall = {}
	local ball = ownBall
	if ball and ball.Parent then
		local size = FindView.inBallSize(Visual, ball.Size.X)
		for index = 1, FindView.shownInBall(Visual, #ballFinds) do
			local attachment = Instance.new("Attachment")
			attachment.Name = `FindInBall_{index}`
			attachment:SetAttribute("FindId", ballFinds[index])
			billboard(ballFinds[index], size, attachment, nil)
			attachment.Parent = ball
			table.insert(inBall, attachment)
		end
		placeInBall()
	end
	publish()
end

local function setOwnBall(part: BasePart?)
	if ownBall == part then
		return
	end
	if ballSizeConnection then
		ballSizeConnection:Disconnect()
		ballSizeConnection = nil
	end
	ownBall = part
	if part then
		ballSizeConnection = part:GetPropertyChangedSignal("Size"):Connect(placeInBall)
	end
	rebuildBall()
end

local function ownerOf(part: Instance): Player?
	local userId = part:GetAttribute(BallConfig.OwnerAttribute)
	return if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
end

local function applyEffect(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local owner = ownerOf(part)
	local effect = owner and owner:GetAttribute(FindsConfig.BallEffectAttribute)
	local existing = part:FindFirstChild(Visual.EffectName)
	if type(effect) == "string" and effect ~= "" then
		if existing == nil then
			local sparkles = Instance.new("Sparkles")
			sparkles.Name = Visual.EffectName
			sparkles.SparkleColor = Rarity.color3(SECRET)
			sparkles.Parent = part
		end
	elseif existing then
		existing:Destroy()
	end
end

local function watchBalls()
	local folder = Workspace:WaitForChild(BallConfig.FolderName)
	local function check(child: Instance)
		applyEffect(child)
		if child:IsA("BasePart") and child:GetAttribute(BallConfig.OwnerAttribute) == player.UserId then
			setOwnBall(child)
		end
	end
	folder.ChildAdded:Connect(check)
	folder.ChildRemoved:Connect(function(child: Instance)
		if child == ownBall then
			setOwnBall(nil)
		end
	end)
	for _, child in folder:GetChildren() do
		check(child)
	end
	local function refreshEffects()
		for _, child in folder:GetChildren() do
			applyEffect(child)
		end
	end
	local function watchPlayer(other: Player)
		other:GetAttributeChangedSignal(FindsConfig.BallEffectAttribute):Connect(refreshEffects)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
end

local function onUpdate(action: any, slot: any, findId: any, position: any)
	local isSlot = FindView.isSlot(NetConfig.Finds, slot)
	if action == "Spawn" then
		if isSlot and FindView.isFind(FindsConfig, findId) and typeof(position) == "Vector3" then
			showSpawned(slot, findId, position)
		end
	elseif action == "Remove" then
		if isSlot then
			removeSpawned(slot)
		end
	elseif action == "Collect" then
		if isSlot then
			removeSpawned(slot)
		end
		if FindView.isFind(FindsConfig, findId) then
			table.insert(ballFinds, findId)
			rebuildBall()
		end
	elseif action == "ClearBall" then
		ballFinds = {}
		rebuildBall()
	elseif action == "Reset" then
		for shownSlot in spawned do
			removeSpawned(shownSlot)
		end
	end
	publish()
end

function FindController.Start()
	if started then
		return
	end
	started = true
	publish()
	local remote = Net.waitForRemote(REMOTE) :: any
	remote.OnClientEvent:Connect(onUpdate)
	task.spawn(watchBalls)
end

return FindController

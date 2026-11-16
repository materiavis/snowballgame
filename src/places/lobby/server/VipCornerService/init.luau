--!strict
-- VipCornerService: the Lobby VIP corner is only for owners of the VIP game pass (concept 7.1,
-- 9.2; ADR 0009, ADR 0015). Server-enforced: every VipCheckInterval the server looks at each
-- character, and a non-VIP root inside any `VipCorner` volume is moved VipPushOutMargin studs
-- out through the nearest side wall. No collision group or client check is involved, so an
-- exploited client cannot keep a character inside.
--
-- Ownership: MarketplaceService:UserOwnsGamePassAsync with Config.Monetization.Gamepasses.Vip
-- (pcall, cached). AssetId 0 is the placeholder: nobody is VIP on a live server until humans fill
-- it in. A failed check counts as "not VIP" for that moment and is asked again. In Studio at
-- PlaceId 0 the switch LobbySimulateVip decides instead. The pass purchase itself is 9.2.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local LobbyConfig = require(Config:WaitForChild("Lobby")) :: any
local MonetizationConfig = require(Config:WaitForChild("Monetization")) :: any
local LobbyAttributes = require(Shared:WaitForChild("LobbyAttributes"))

local LobbyMap = require(script.Parent:WaitForChild("LobbyMap"))

local MapConfig = LobbyMap.Config
local Box = LobbyMap.Box

local VIP_SWITCH = "LobbySimulateVip"

local VipCornerService = {}

local studioTools = RunService:IsStudio() and game.PlaceId == 0
local started = false

local function log(message: string)
	if RunService:IsStudio() then
		print(`[VipCornerService] {message}`)
	end
end

local function passId(): number
	local id = MonetizationConfig.Gamepasses.Vip.AssetId
	return if type(id) == "number" then id else 0
end

local function queryPass(userId: number): boolean?
	local ok, owns = pcall(function(): boolean
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId())
	end)
	if not ok then
		warn(`[VipCornerService] pass check for {userId} failed: {owns}`)
		return nil
	end
	return owns == true
end

local cache = LobbyMap.AnswerCache.new(queryPass, LobbyConfig.VipOwnershipRecheck, os.clock)
-- Checks run in the background, so the corner loop never waits for a web call.
local answers: { [number]: boolean } = {}
local asking: { [number]: boolean } = {}

local function refresh(player: Player)
	local userId = player.UserId
	if asking[userId] then
		return
	end
	asking[userId] = true
	task.spawn(function()
		local answer = cache.get(userId)
		asking[userId] = nil
		if player.Parent == Players then
			answers[userId] = answer == true
		end
	end)
end

-- Never yields: the last answer, with a background refresh (the cache decides when to ask).
local function hasAccess(player: Player): boolean
	if studioTools then
		return ServerScriptService:GetAttribute(VIP_SWITCH) == true
	end
	if passId() <= 0 then
		return false
	end
	refresh(player)
	return answers[player.UserId] == true
end

local function volumeHolding(root: BasePart, volumes: { Instance }): BasePart?
	for _, volume in volumes do
		if LobbyMap.contains(volume :: BasePart, root.Position) then
			return volume :: BasePart
		end
	end
	return nil
end

local function pushOut(player: Player, root: BasePart, volume: BasePart)
	local localPoint = volume.CFrame:PointToObjectSpace(root.Position)
	local size = { volume.Size.X, volume.Size.Y, volume.Size.Z }
	local x, y, z = Box.pushOut(localPoint.X, localPoint.Y, localPoint.Z, size, LobbyConfig.VipPushOutMargin)
	local target = volume.CFrame:PointToWorldSpace(Vector3.new(x, y, z))
	local character = player.Character :: Model
	character:PivotTo(CFrame.new(target) * root.CFrame.Rotation)
end

local function checkPlayer(player: Player, volumes: { Instance })
	local root = LobbyMap.rootOf(player)
	local volume = if root then volumeHolding(root, volumes) else nil
	if root == nil or volume == nil then
		return
	end
	local access = hasAccess(player)
	if studioTools then
		player:SetAttribute(LobbyAttributes.VIP_ACCESS, access)
	end
	if access then
		return
	end
	pushOut(player, root, volume)
	if studioTools then
		local count = ((player:GetAttribute(LobbyAttributes.VIP_EJECTIONS) :: number?) or 0) + 1
		player:SetAttribute(LobbyAttributes.VIP_EJECTIONS, count)
	end
	log(`{player.Name} ({player.UserId}) moved out of {volume:GetFullName()}: no VIP pass`)
end

local function setUp()
	if started then
		return
	end
	started = true

	local volumes = LobbyMap.bindTag(MapConfig.Tags.VipCorner, LobbyMap.rules.checkPart, function(instance)
		log(`corner bound {instance:GetFullName()}`)
	end)
	LobbyMap.warnCount(MapConfig.Tags.VipCorner, #volumes(), "some")

	-- Ask early, so a VIP is not moved out while the first answer is still on its way.
	local function onPlayerAdded(player: Player)
		hasAccess(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		cache.forget(player.UserId)
		answers[player.UserId] = nil
	end)
	if studioTools and ServerScriptService:GetAttribute(VIP_SWITCH) == nil then
		ServerScriptService:SetAttribute(VIP_SWITCH, false)
	end

	task.spawn(function()
		while true do
			task.wait(LobbyConfig.VipCheckInterval)
			local list = volumes()
			if #list > 0 then
				for _, player in Players:GetPlayers() do
					checkPlayer(player, list)
				end
			end
		end
	end)
	print(`[VipCornerService] started volumes={#volumes()} passId={passId()} studioSwitches={studioTools}`)
end

function VipCornerService.Start()
	setUp()
end

return VipCornerService

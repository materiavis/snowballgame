--!strict
-- Egg stations on the client (concept 7.9, 8.5, 6.5, ADR 0013): a label with price and chances
-- at every station the server bound, the hatch request, the missing-coins message and the
-- hatch reveal. Display only: the server decides price, coins, room and the roll.
--
-- Binds prompts with Config.Map.EggStation.PromptTag (the server creates them only on stations
-- it accepted; they stream in with the station). A trigger sends `EggHatch()` without
-- arguments when the Coins attribute reaches the price, else it shows "Need … more" on the
-- label and sends nothing. The reveal starts when the server writes `EggLastHatch`.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EggsConfig = require(Config:WaitForChild("Eggs")) :: any
local MapConfig = require(Config:WaitForChild("Map")) :: any
local UiConfig = require(Config:WaitForChild("Ui")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any
local PetCatalogue = require(Shared:WaitForChild("PetCatalogue")) :: any
local Rarity = require(Shared:WaitForChild("Rarity")) :: any
local Rng = require(Shared:WaitForChild("Rng")) :: any

local EggLabel = require(script:WaitForChild("EggLabel"))
local EggStationView = require(script:WaitForChild("EggStationView"))

local REMOTE = "EggHatch"
local COINS_ATTRIBUTE = "Coins"
local STATUS_ATTRIBUTE = "DataLoadStatus"
local LAST_HATCH = "EggLastHatch"

local EggStationController = {}

local viewDeps = {
	catalogue = PetCatalogue,
	rarity = Rarity,
	text = UiConfig.Text,
	multiplierDecimals = UiConfig.PetsWindow.MultiplierDecimals,
}

local function stationOf(prompt: Instance): Instance?
	local node = prompt.Parent
	while node ~= nil and node ~= workspace do
		if CollectionService:HasTag(node, MapConfig.Tags.EggStation) then
			return node
		end
		node = node.Parent
	end
	return nil
end

function EggStationController.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stationConfig = MapConfig.EggStation
	local labels: { [Instance]: EggLabel.Label } = {}
	local lastUsed: EggLabel.Label? = nil

	local remote: RemoteEvent? = nil
	task.spawn(function()
		remote = Net.waitForRemote(REMOTE) :: RemoteEvent
	end)

	local function eggOf(prompt: Instance): (number?, boolean)
		local egg = prompt:GetAttribute(stationConfig.EggAttribute)
		local open = prompt:GetAttribute(stationConfig.OpenAttribute) == true
		if type(egg) ~= "number" or egg % 1 ~= 0 or egg < 1 or egg > Formulas.Pets.eggCount then
			return nil, false
		end
		return egg, open
	end

	local function refresh(prompt: Instance)
		local label = labels[prompt]
		local egg, open = eggOf(prompt)
		if label == nil or egg == nil then
			return
		end
		local isOpen = open and PetCatalogue.isAvailable(egg)
		label.show({
			title = PetCatalogue.eggName(egg) or UiConfig.Text.EggStationObject,
			price = if isOpen
				then EggStationView.priceText(Formulas.Pets.eggPrice(egg), NumberFormat.price, UiConfig.Text)
				else nil,
			rows = if isOpen then EggStationView.oddsRows(egg, Rng.eggOdds(egg, false), viewDeps) else {},
			open = isOpen,
		})
	end

	local function bind(prompt: Instance)
		if labels[prompt] or not prompt:IsA("ProximityPrompt") then
			return
		end
		local station = stationOf(prompt)
		local primary = prompt.Parent
		if station == nil or primary == nil then
			return
		end
		local anchor = station:FindFirstChild(MapConfig.LabelAnchorName, true)
		local adornee: Instance = primary
		local offset = UiConfig.EggStationLabel.OffsetStuds
		local studs = Vector3.new(offset[1], offset[2], offset[3])
		if anchor and anchor:IsA("Attachment") then
			adornee = anchor
			studs = Vector3.zero
		end
		labels[prompt] = EggLabel.new(playerGui, adornee, (eggOf(prompt)) or 0, studs)
		-- The server writes the egg and the open flag right after creating the prompt.
		prompt.AttributeChanged:Connect(function()
			refresh(prompt)
		end)
		refresh(prompt)
	end

	local function unbind(prompt: Instance)
		local label = labels[prompt]
		if label then
			labels[prompt] = nil
			if lastUsed == label then
				lastUsed = nil
			end
			label.destroy()
		end
	end

	local tag = stationConfig.PromptTag
	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbind)
	for _, prompt in CollectionService:GetTagged(tag) do
		bind(prompt)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if not CollectionService:HasTag(prompt, tag) then
			return
		end
		local label = labels[prompt]
		local egg, open = eggOf(prompt)
		if label == nil or egg == nil or not open then
			return
		end
		if player:GetAttribute(STATUS_ATTRIBUTE) ~= "Loaded" then
			return
		end
		-- A display hint from the server's Coins attribute; the server checks again.
		local missing = EggStationView.missingText(
			Formulas.Pets.eggPrice(egg),
			player:GetAttribute(COINS_ATTRIBUTE),
			NumberFormat.price,
			UiConfig.Text
		)
		if missing then
			label.showMissing(missing)
			return
		end
		lastUsed = label
		if remote then
			remote:FireServer()
		end
	end)

	player:GetAttributeChangedSignal(LAST_HATCH):Connect(function()
		local _, kind = EggStationView.parseHatch(player:GetAttribute(LAST_HATCH))
		local view = if kind then EggStationView.reveal(kind, viewDeps) else nil
		-- The station the player used; after a Studio purchase switch any bound station.
		local label = lastUsed
		if label == nil then
			for _, any in labels do
				label = any
				break
			end
		end
		if view == nil or label == nil then
			return
		end
		local reveal = EggsConfig.Reveal
		label.reveal(view, reveal.WobbleSeconds, reveal.ShowSeconds, reveal.WobbleDegrees, reveal.WobbleSpeed)
	end)
end

return EggStationController

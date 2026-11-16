--!strict
-- Barrier stations on this client (#39, concept 7.6, ADR 0009, ADR 0014). Only barriers the
-- server bound (attribute BarrierZone set) are used; the client never validates the map.
-- For each one, from this player's view:
--   * label "Zone N · price" (or "Zone N · Coming soon" while it cannot open), hidden once open,
--   * a prompt while this player can buy it (ZoneView.canBuy),
--   * passability: once zone N is unlocked its parts go into the OpenBarrier collision group
--     locally, so only this player's character and ball pass. Group changes do not replicate,
--     and no part's CanCollide changes (the reviewed Simulator rule),
--   * walking into it (or the prompt) opens the unlock window or shows the missing amount.
-- Labels and prompts are rebuilt when the barrier streams in again.
--
-- Client-local diagnostics on the LocalPlayer (read-only for the playtester, not replicated):
-- ZoneOpenBarrierParts (parts in OpenBarrier), ZoneLastWalkIn ("zone 2 Window", ...).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MapConfig = require(Config:WaitForChild("Map")) :: any
local UiConfig = require(Config:WaitForChild("Ui")) :: any
local ZoneUi = require(Config:WaitForChild("ZoneUi")) :: any
local Formulas = require(Shared:WaitForChild("Formulas")) :: any
local NumberFormat = require(Shared:WaitForChild("NumberFormat")) :: any
local Prompts = require(Shared:WaitForChild("Prompts"))
local ZoneAttributes = require(Shared:WaitForChild("ZoneAttributes"))
local ZoneView = require(script.Parent:WaitForChild("ZoneView"))

export type Callbacks = {
	-- With enough coins: open the unlock window for `zone` (the zone the barrier opens).
	openWindow: (zone: number, price: number) -> (),
	-- With too few coins: show the missing amount.
	showMissing: (missing: number) -> (),
}

type Bound = {
	model: Model,
	label: BillboardGui?,
	prompt: ProximityPrompt?,
	originalGroups: { [BasePart]: string },
	inside: boolean,
}

local COINS_ATTRIBUTE = "Coins"
local STATUS_ATTRIBUTE = "DataLoadStatus"
local OPEN_PARTS_ATTRIBUTE = "ZoneOpenBarrierParts"
local LAST_WALK_IN_ATTRIBUTE = "ZoneLastWalkIn"
local LABEL_NAME = "BarrierLabel"

local barrierConfig = MapConfig.Barrier
local labelConfig = ZoneUi.Label

local Barriers = {}

function Barriers.start(callbacks: Callbacks)
	local player = Players.LocalPlayer
	local bound: { [Model]: Bound } = {}

	local function unlockedSet(): ZoneView.Set?
		return ZoneView.toSet(
			ZoneAttributes.decode(player:GetAttribute(ZoneAttributes.UNLOCKED), Formulas.Zones.isZone)
		)
	end

	local function factsOf(model: Model): ZoneView.WalkInFacts?
		local zone = model:GetAttribute(barrierConfig.ZoneAttribute)
		if not Formulas.Zones.isZone(zone) then
			return nil
		end
		return {
			loaded = player:GetAttribute(STATUS_ATTRIBUTE) == "Loaded",
			unlocked = unlockedSet(),
			barrierZone = zone,
			canOpen = model:GetAttribute(barrierConfig.CanOpenAttribute) == true,
			coins = player:GetAttribute(COINS_ATTRIBUTE),
			price = Formulas.Zones.barrierPrice(zone),
		}
	end

	local function countOpenParts()
		local count = 0
		for _, entry in bound do
			for part in entry.originalGroups do
				if part.CollisionGroup == barrierConfig.OpenCollisionGroup then
					count += 1
				end
			end
		end
		player:SetAttribute(OPEN_PARTS_ATTRIBUTE, count)
	end

	local function setPassable(entry: Bound, open: boolean)
		if open and not PhysicsService:IsCollisionGroupRegistered(barrierConfig.OpenCollisionGroup) then
			-- The server registers it at start; try again once it has replicated.
			task.delay(1, function()
				if bound[entry.model] == entry then
					setPassable(entry, true)
					countOpenParts()
				end
			end)
			return
		end
		for _, part in entry.model:GetDescendants() do
			if part:IsA("BasePart") then
				if entry.originalGroups[part] == nil then
					entry.originalGroups[part] = part.CollisionGroup
				end
				part.CollisionGroup = if open then barrierConfig.OpenCollisionGroup else entry.originalGroups[part]
			end
		end
	end

	local function labelParent(model: Model): (Instance?, Vector3)
		local anchor = model:FindFirstChild(MapConfig.LabelAnchorName, true)
		if anchor and anchor:IsA("Attachment") then
			return anchor, Vector3.zero
		end
		local primary = model.PrimaryPart
		if primary == nil then
			return nil, Vector3.zero
		end
		return primary, Vector3.new(0, primary.Size.Y / 2 + labelConfig.OffsetStuds, 0)
	end

	local function makeLabel(model: Model): BillboardGui?
		local parent, offset = labelParent(model)
		if parent == nil then
			return nil
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = LABEL_NAME
		gui.Size = UDim2.fromScale(labelConfig.WidthStuds, labelConfig.HeightStuds)
		gui.StudsOffset = offset
		gui.MaxDistance = labelConfig.MaxDistance
		gui.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.AutoLocalize = false -- carries a zone number and a price
		text.Font = (Enum.Font :: any)[UiConfig.Fonts.Bold]
		text.TextColor3 = Color3.fromRGB(UiConfig.Colours.Text[1], UiConfig.Colours.Text[2], UiConfig.Colours.Text[3])
		text.TextStrokeTransparency = 0.3
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = labelConfig.TextSize
		constraint.Parent = text
		text.Parent = gui
		gui.Parent = parent
		return gui
	end

	local function update(entry: Bound)
		local facts = factsOf(entry.model)
		if facts == nil then
			return
		end
		local zone = facts.barrierZone
		local unlocked = facts.unlocked

		local labelText =
			ZoneView.barrierLabel(zone, facts.canOpen, unlocked, UiConfig.Text, NumberFormat.price(facts.price))
		if entry.label == nil or entry.label.Parent == nil then
			entry.label = makeLabel(entry.model)
		end
		local label = entry.label
		if label then
			label.Enabled = labelText ~= nil
			local textLabel = label:FindFirstChild("Text") :: TextLabel?
			if textLabel then
				textLabel.Text = labelText or ""
			end
		end

		local buyable = ZoneView.canBuy(facts)
		if buyable and (entry.prompt == nil or entry.prompt.Parent == nil) and entry.model.PrimaryPart then
			entry.prompt =
				Prompts.create("Barrier", entry.model.PrimaryPart :: BasePart, { tag = barrierConfig.PromptTag })
		elseif not buyable and entry.prompt then
			entry.prompt:Destroy()
			entry.prompt = nil
		end

		local open = unlocked ~= nil and unlocked[zone + 1] == true and facts.loaded
		setPassable(entry, open)
		countOpenParts()
	end

	local function walkIn(model: Model, how: string)
		local facts = factsOf(model)
		if facts == nil then
			return
		end
		local action, missing = ZoneView.walkIn(facts)
		player:SetAttribute(LAST_WALK_IN_ATTRIBUTE, `zone {facts.barrierZone + 1} {action} {how}`)
		if action == "Window" then
			callbacks.openWindow(facts.barrierZone + 1, facts.price)
		elseif action == "NeedMore" and missing then
			callbacks.showMissing(missing)
		end
	end

	local function bind(instance: Instance)
		if not instance:IsA("Model") or bound[instance] then
			return
		end
		local entry: Bound = { model = instance, label = nil, prompt = nil, originalGroups = {}, inside = false }
		bound[instance] = entry
		instance:GetAttributeChangedSignal(barrierConfig.ZoneAttribute):Connect(function()
			update(entry)
		end)
		instance:GetAttributeChangedSignal(barrierConfig.CanOpenAttribute):Connect(function()
			update(entry)
		end)
		-- Atomic streaming delivers the parts with the model; this catches late additions.
		instance.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				task.defer(update, entry)
			end
		end)
		update(entry)
	end

	local function unbind(instance: Instance)
		local entry = bound[instance :: Model]
		if entry == nil then
			return
		end
		bound[instance :: Model] = nil
		if entry.prompt then
			entry.prompt:Destroy()
		end
		if entry.label then
			entry.label:Destroy()
		end
		countOpenParts()
	end

	local function updateAll()
		for _, entry in bound do
			update(entry)
		end
	end

	CollectionService:GetInstanceAddedSignal(MapConfig.Tags.Barrier):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(MapConfig.Tags.Barrier):Connect(unbind)
	for _, instance in CollectionService:GetTagged(MapConfig.Tags.Barrier) do
		bind(instance)
	end
	player:GetAttributeChangedSignal(ZoneAttributes.UNLOCKED):Connect(updateAll)
	player:GetAttributeChangedSignal(STATUS_ATTRIBUTE):Connect(updateAll)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if not CollectionService:HasTag(prompt, barrierConfig.PromptTag) then
			return
		end
		local model = prompt:FindFirstAncestorOfClass("Model")
		while model and not bound[model] do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model then
			walkIn(model, "Prompt")
		end
	end)

	-- Walking in: the root inside the barrier's box grown by WalkInMargin. Fires once per entry.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < ZoneUi.WalkInInterval then
			return
		end
		elapsed = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			return
		end
		for model, entry in bound do
			if model.Parent == nil or model:GetAttribute(barrierConfig.ZoneAttribute) == nil then
				entry.inside = false
				continue
			end
			local cframe, size = model:GetBoundingBox()
			local localPosition = cframe:PointToObjectSpace(root.Position)
			local half = size / 2 + Vector3.one * ZoneUi.WalkInMargin
			local inside = math.abs(localPosition.X) <= half.X
				and math.abs(localPosition.Y) <= half.Y
				and math.abs(localPosition.Z) <= half.Z
			if inside and not entry.inside then
				entry.inside = true
				walkIn(model, "Walk")
			elseif not inside then
				entry.inside = false
			end
		end
	end)
end

return table.freeze(Barriers)

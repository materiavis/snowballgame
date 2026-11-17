--!strict
-- Placeholder shapes for following pets (ADR 0013): no pet models exist yet (concept 7.9 appendix
-- "Pet-Katalog", import not tested), so a pet is a ball in its rarity colour. Client-only parts:
-- anchored, no collision, no touch, no queries and no shadow, so they never touch physics,
-- raycasts or the ball (ADR 0002) and stay cheap on phones.
--
-- Own pets (detailed): body, head and a small name label with stars. Foreign pets (simplified,
-- ADR 0003 R2): one part, no label. Model attributes: Kind, Owner, Simplified.

export type Visual = {
	model: Model,
	parts: { BasePart }, -- moved together; parts[1] is the body
	offsets: { CFrame }, -- each part relative to the body
	size: number,
}

local PetModels = {}

local function ball(name: string, size: number, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	return part
end

export type Options = {
	uid: string,
	kind: string,
	owner: number,
	simplified: boolean,
	colour: Color3,
	labelText: string?, -- own pets: "Snow Hare ★"
	follow: any, -- Config.Pets.Follow
}

function PetModels.create(options: Options): Visual
	local follow = options.follow
	local model = Instance.new("Model")
	model.Name = options.uid
	model:SetAttribute("Kind", options.kind)
	model:SetAttribute("Owner", options.owner)
	model:SetAttribute("Simplified", options.simplified)

	if options.simplified then
		local body = ball("Body", follow.ForeignBodySize, options.colour)
		body.Parent = model
		model.PrimaryPart = body
		return { model = model, parts = { body }, offsets = { CFrame.identity }, size = follow.ForeignBodySize }
	end

	local bodySize, headSize = follow.OwnBodySize, follow.OwnHeadSize
	local body = ball("Body", bodySize, options.colour)
	body.Parent = model
	local headOffset = CFrame.new(0, (bodySize + headSize) * 0.4, -bodySize * 0.15)
	local head = ball("Head", headSize, options.colour:Lerp(Color3.new(1, 1, 1), 0.25))
	head.Parent = model
	model.PrimaryPart = body

	if options.labelText then
		local gui = Instance.new("BillboardGui")
		gui.Name = "NameLabel"
		gui.Adornee = head
		gui.Size = UDim2.fromOffset(120, 24)
		gui.StudsOffsetWorldSpace = Vector3.new(0, headSize, 0)
		gui.MaxDistance = follow.LabelMaxDistance
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = options.labelText
		label.TextScaled = true
		label.TextColor3 = options.colour
		label.TextStrokeTransparency = 0.3
		label.Font = Enum.Font.GothamBold
		label.Parent = gui
		gui.Parent = model
	end

	return {
		model = model,
		parts = { body, head },
		offsets = { CFrame.identity, headOffset },
		size = bodySize,
	}
end

return table.freeze(PetModels)

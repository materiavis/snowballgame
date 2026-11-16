--!strict
-- The label of one egg station (concept 7.9, 8.5, ADR 0013): a BillboardGui at the station's
-- LabelAnchor (or above its PrimaryPart) with the egg, its price and one line per pet with its
-- rarity (stars and name in the rarity colour) and chance. Below it a message line for "Need …
-- more". The hatch reveal replaces the chances for a moment: the egg wobbles, then the pet shows.
-- Instances only; the texts come from EggStationView.
--
-- Playtest handles: PlayerGui.EggStationLabel (attribute EggIndex; ResetOnSpawn off) with
-- Panel.Title, Panel.Price, Panel.Odds.<Rarity>.{Pet, Rarity, Chance}, Panel.MissingAmount,
-- Panel.Closed and Reveal.{Egg, Status, PetName, Rarity, Bonus}.

local RunService = game:GetService("RunService")

local Client = script.Parent.Parent.Parent
local UiFolder = Client:WaitForChild("Ui")
local Components = require(UiFolder:WaitForChild("Components"))
local Theme = require(UiFolder:WaitForChild("Theme"))

local Ui = Theme.Config

export type View = {
	title: string,
	price: string?, -- nil for a closed egg
	rows: { { rarity: string, pet: string, rarityText: string, chance: string, rgb: { number } } },
	open: boolean,
}

export type RevealView = { name: string, rarityText: string, bonusText: string, rgb: { number } }

export type Label = {
	gui: BillboardGui,
	show: (view: View) -> (),
	showMissing: (text: string) -> (),
	reveal: (view: RevealView, wobbleSeconds: number, showSeconds: number, degrees: number, speed: number) -> (),
	destroy: () -> (),
}

local EggLabel = {}

local function colour(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function line(name: string, size: number, options: any?): TextLabel
	local label = Components.label(name, "", size, 2, options)
	label.Size = UDim2.fromScale(1, 1)
	return label
end

function EggLabel.new(parent: Instance, adornee: Instance, egg: number, offset: Vector3): Label
	local cfg = Ui.EggStationLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggStationLabel"
	gui:SetAttribute("EggIndex", egg)
	gui.Adornee = adornee
	-- Scale of a BillboardGui is in studs, so the label belongs to the station.
	gui.Size = UDim2.fromScale(cfg.SizeStuds[1], cfg.SizeStuds[2])
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = cfg.MaxDistance
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.AlwaysOnTop = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Surface
	panel.BackgroundTransparency = Ui.PanelTransparency
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = line("Title", cfg.TitleTextSize, { bold = true })
	title.LayoutOrder = 1
	title.Parent = panel
	local price = line("Price", cfg.LineTextSize, { bold = true, autoLocalize = false })
	price.TextColor3 = Theme.Max
	price.LayoutOrder = 2
	price.Parent = panel
	local odds = Instance.new("Frame")
	odds.Name = "Odds"
	odds.BackgroundTransparency = 1
	odds.LayoutOrder = 3
	odds.Parent = panel
	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = odds
	local closed = line("Closed", cfg.LineTextSize, { muted = true })
	closed.Text = Ui.Text.EggComingSoon
	closed.LayoutOrder = 4
	closed.Parent = panel
	local missing = line("MissingAmount", cfg.LineTextSize, { bold = true, autoLocalize = false })
	missing.TextColor3 = Theme.Max
	missing.LayoutOrder = 5
	missing.Visible = false
	missing.Parent = panel

	local reveal = Instance.new("Frame")
	reveal.Name = "Reveal"
	reveal.Size = UDim2.fromScale(1, 1)
	reveal.BackgroundColor3 = Theme.Surface
	reveal.BorderSizePixel = 0
	reveal.Visible = false
	reveal.Parent = gui
	local eggShape = Instance.new("Frame")
	eggShape.Name = "Egg"
	eggShape.AnchorPoint = Vector2.new(0.5, 0.5)
	eggShape.Position = UDim2.fromScale(0.5, 0.35)
	eggShape.Size = UDim2.fromScale(0.35, 0.45)
	eggShape.BackgroundColor3 = Theme.Text
	eggShape.Parent = reveal
	local eggCorner = Instance.new("UICorner")
	eggCorner.CornerRadius = UDim.new(0.5, 0)
	eggCorner.Parent = eggShape
	local status = line("Status", cfg.TitleTextSize, { bold = true })
	status.Text = Ui.Text.EggHatching
	status.Position = UDim2.fromScale(0, 0.65)
	status.Size = UDim2.fromScale(1, 0.2)
	status.Parent = reveal
	local petName = line("PetName", cfg.TitleTextSize, { bold = true })
	petName.Position = UDim2.fromScale(0, 0.15)
	petName.Size = UDim2.fromScale(1, 0.25)
	petName.Parent = reveal
	local rarityLabel = line("Rarity", cfg.TitleTextSize, { bold = true })
	rarityLabel.Position = UDim2.fromScale(0, 0.42)
	rarityLabel.Size = UDim2.fromScale(1, 0.22)
	rarityLabel.Parent = reveal
	local bonus = line("Bonus", cfg.LineTextSize, { bold = true, autoLocalize = false })
	bonus.Position = UDim2.fromScale(0, 0.68)
	bonus.Size = UDim2.fromScale(1, 0.2)
	bonus.Parent = reveal

	gui.Parent = parent

	local rowFrames: { Frame } = {}
	local missingToken = 0
	local revealToken = 0
	local wobble: RBXScriptConnection? = nil

	local function show(view: View)
		title.Text = view.title
		price.Text = view.price or ""
		price.Visible = view.open
		closed.Visible = not view.open
		odds.Visible = view.open
		for _, frame in rowFrames do
			frame:Destroy()
		end
		table.clear(rowFrames)
		local rows = if view.open then #view.rows else 0
		-- Title counts one and a half lines; the message line keeps its place.
		local lines = 1.5 + 1 + rows + 1
		local unit = 1 / lines
		title.Size = UDim2.fromScale(1, 1.5 * unit)
		price.Size = UDim2.fromScale(1, unit)
		closed.Size = UDim2.fromScale(1, unit)
		missing.Size = UDim2.fromScale(1, unit)
		odds.Size = UDim2.fromScale(1, rows * unit)
		for index, row in view.rows do
			if not view.open then
				break
			end
			local frame = Instance.new("Frame")
			frame.Name = row.rarity
			frame.BackgroundTransparency = 1
			frame.LayoutOrder = index
			frame.Size = UDim2.fromScale(1, 1 / math.max(rows, 1))
			local pet = line("Pet", cfg.LineTextSize)
			pet.Text = row.pet
			pet.TextXAlignment = Enum.TextXAlignment.Left
			pet.Size = UDim2.fromScale(0.4, 1)
			pet.Position = UDim2.fromScale(0.04, 0)
			pet.Parent = frame
			local rarity = line("Rarity", cfg.LineTextSize, { bold = true })
			rarity.Text = row.rarityText
			rarity.TextColor3 = colour(row.rgb)
			rarity.Size = UDim2.fromScale(0.36, 1)
			rarity.Position = UDim2.fromScale(0.44, 0)
			rarity.Parent = frame
			local chance = line("Chance", cfg.LineTextSize, { bold = true, autoLocalize = false })
			chance.Text = row.chance
			chance.TextXAlignment = Enum.TextXAlignment.Right
			chance.Size = UDim2.fromScale(0.16, 1)
			chance.Position = UDim2.fromScale(0.8, 0)
			chance.Parent = frame
			frame.Parent = odds
			table.insert(rowFrames, frame)
		end
	end

	local function showMissing(text: string)
		missingToken += 1
		local token = missingToken
		missing.Text = text
		missing.Visible = true
		task.delay(cfg.MissingMessageSeconds, function()
			if missingToken == token then
				missing.Visible = false
			end
		end)
	end

	local function stopWobble()
		if wobble then
			wobble:Disconnect()
			wobble = nil
		end
		eggShape.Rotation = 0
	end

	local function revealPet(
		view: RevealView,
		wobbleSeconds: number,
		showSeconds: number,
		degrees: number,
		speed: number
	)
		revealToken += 1
		local token = revealToken
		stopWobble()
		panel.Visible = false
		reveal.Visible = true
		eggShape.Visible = true
		status.Visible = true
		petName.Visible = false
		rarityLabel.Visible = false
		bonus.Visible = false
		local started = os.clock()
		wobble = RunService.RenderStepped:Connect(function()
			eggShape.Rotation = degrees * math.sin((os.clock() - started) * speed)
		end)
		task.delay(wobbleSeconds, function()
			if revealToken ~= token then
				return
			end
			stopWobble()
			eggShape.Visible = false
			status.Visible = false
			local tint = colour(view.rgb)
			petName.Text = view.name
			rarityLabel.Text = view.rarityText
			rarityLabel.TextColor3 = tint
			bonus.Text = view.bonusText
			reveal.BackgroundColor3 = Theme.Surface:Lerp(tint, 0.35)
			petName.Visible = true
			rarityLabel.Visible = true
			bonus.Visible = true
			task.delay(showSeconds, function()
				if revealToken == token then
					reveal.Visible = false
					reveal.BackgroundColor3 = Theme.Surface
					panel.Visible = true
				end
			end)
		end)
	end

	return {
		gui = gui,
		show = show,
		showMissing = showMissing,
		reveal = revealPet,
		destroy = function()
			revealToken += 1
			stopWobble()
			gui:Destroy()
		end,
	}
end

return table.freeze(EggLabel)

--!strict
-- World symbols of the Simulator's onboarding hints (concept 10.1, ADR 0017): a chevron trail
-- that follows the player, a pulsing beacon over a target and a pulsing outline on a station.
-- Client-only parts in Workspace, no collision, no queries, no assets. The Lobby's fixed arrow
-- and portal rim are GuideArrow (ADR 0015), which lives in the Lobby's client folder.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

export type Chevron = { x: number, z: number, yaw: number }
export type Trail = { set: (chevrons: { Chevron }, y: number) -> (), count: () -> number, destroy: () -> () }
export type Beacon = { move: (position: Vector3) -> (), destroy: () -> () }
export type Pulse = { destroy: () -> () }

local TutorialWorld = {}

local ARM_ANGLE = math.rad(35)

local function rgb(list: { number }): Color3
	return Color3.fromRGB(list[1], list[2], list[3])
end

local function ghost(name: string, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = colour
	return part
end

local function pulse(instance: Instance, property: string, from: number, to: number, seconds: number): Tween
	(instance :: any)[property] = from
	local info = TweenInfo.new(seconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(instance, info, { [property] = to })
	tween:Play()
	return tween
end

-- A folder of chevrons that is moved, not rebuilt, on every set().
function TutorialWorld.trail(name: string, display: any): Trail
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	local colour = rgb(display.ColourRGB)
	local size = display.ArmSize
	local arms: { Part } = {}
	local tweens: { Tween } = {}
	local shown = 0

	local function arm(index: number): Part
		local part = arms[index]
		if part == nil then
			part = ghost("Arm", colour)
			part.Size = Vector3.new(size[3], size[2], size[1])
			part.Parent = folder
			arms[index] = part
			table.insert(tweens, pulse(part, "Transparency", 0, 0.6, display.PulseSeconds))
		end
		return part
	end

	local function set(chevrons: { Chevron }, y: number)
		local index = 0
		for _, chevron in chevrons do
			local base = CFrame.new(chevron.x, y, chevron.z) * CFrame.Angles(0, chevron.yaw, 0)
			for _, side in { -1, 1 } do
				index += 1
				local part = arm(index)
				part.CFrame = base * CFrame.Angles(0, side * ARM_ANGLE, 0) * CFrame.new(0, 0, size[1] / 2)
				part.LocalTransparencyModifier = 0
			end
		end
		for i = index + 1, #arms do
			arms[i].LocalTransparencyModifier = 1
		end
		shown = #chevrons
		folder:SetAttribute("Chevrons", shown)
	end

	return {
		set = set,
		count = function()
			return shown
		end,
		destroy = function()
			for _, tween in tweens do
				tween:Cancel()
			end
			folder:Destroy()
		end,
	}
end

-- A tall pulsing pillar standing on `position`.
function TutorialWorld.beacon(name: string, position: Vector3, display: any): Beacon
	local size = display.BeaconSize
	local part = ghost(name, rgb(display.ColourRGB))
	part.Size = Vector3.new(size[1], size[2], size[3])
	local function move(at: Vector3)
		part.CFrame = CFrame.new(at + Vector3.new(0, size[2] / 2, 0))
	end
	move(position)
	part.Parent = Workspace
	local tween = pulse(part, "Transparency", 0.2, 0.8, display.PulseSeconds)
	return {
		move = move,
		destroy = function()
			tween:Cancel()
			part:Destroy()
		end,
	}
end

-- A pulsing outline on `model` (the barrier). Removed with destroy or with the model.
function TutorialWorld.pulse(name: string, model: Model, display: any): Pulse
	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.FillColor = rgb(display.ColourRGB)
	highlight.OutlineColor = rgb(display.ColourRGB)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	local fill = pulse(highlight, "FillTransparency", 0.5, 1, display.PulseSeconds)
	local outline = pulse(highlight, "OutlineTransparency", 0, 0.8, display.PulseSeconds)
	return {
		destroy = function()
			fill:Cancel()
			outline:Cancel()
			highlight:Destroy()
		end,
	}
end

return table.freeze(TutorialWorld)

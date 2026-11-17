--!strict
-- A pulsing ground arrow and a pulsing rim (concept 7.1, 10.1; ADR 0015). Client-only visuals,
-- reusable: the first-join arrow uses it now, #42 (onboarding) the Multiplayer arrow later.
-- Spielraum 7.1: the shape of the arrow. Chevrons from ArrowPath, made of two thin arms each.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ArrowPath = require(script.Parent:WaitForChild("ArrowPath"))

export type Style = {
	colour: Color3,
	spacing: number,
	armSize: { number }, -- studs {length, thickness, width}
	height: number,
	gap: number,
	pulseSeconds: number,
}

export type Handle = { destroy: () -> () }

local GuideArrow = {}

local ARM_ANGLE = math.rad(35)

local function pulse(instance: Instance, property: string, from: number, to: number, seconds: number): Tween
	(instance :: any)[property] = from
	local info = TweenInfo.new(seconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(instance, info, { [property] = to })
	tween:Play()
	return tween
end

-- A ground arrow from `from` to `to` (heights: `from.Y` + style.height). The folder lives in
-- Workspace and exists only on this client.
function GuideArrow.ground(name: string, from: Vector3, to: Vector3, style: Style): Handle
	local folder = Instance.new("Folder")
	folder.Name = name
	local tweens: { Tween } = {}
	local y = from.Y + style.height
	for _, chevron in ArrowPath.chevrons(from.X, from.Z, to.X, to.Z, style.spacing, style.gap) do
		local base = CFrame.new(chevron.x, y, chevron.z) * CFrame.Angles(0, chevron.yaw, 0)
		for _, side in { -1, 1 } do
			local arm = Instance.new("Part")
			arm.Name = "Arm"
			arm.Anchored = true
			arm.CanCollide = false
			arm.CanQuery = false
			arm.CanTouch = false
			arm.CastShadow = false
			arm.Material = Enum.Material.Neon
			arm.Color = style.colour
			-- Length along the arm's own z: the two arms meet at the chevron's tip (towards the
			-- target) and open backwards.
			arm.Size = Vector3.new(style.armSize[3], style.armSize[2], style.armSize[1])
			arm.CFrame = base * CFrame.Angles(0, side * ARM_ANGLE, 0) * CFrame.new(0, 0, style.armSize[1] / 2)
			arm.Parent = folder
			table.insert(tweens, pulse(arm, "Transparency", 0, 0.6, style.pulseSeconds))
		end
	end
	folder.Parent = Workspace
	return {
		destroy = function()
			for _, tween in tweens do
				tween:Cancel()
			end
			folder:Destroy()
		end,
	}
end

-- A pulsing outline around `model` (the portal rim). Removed with destroy or with the model.
function GuideArrow.rim(name: string, model: Model, style: Style): Handle
	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.FillTransparency = 1
	highlight.OutlineColor = style.colour
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	local tween = pulse(highlight, "OutlineTransparency", 0, 0.8, style.pulseSeconds)
	return {
		destroy = function()
			tween:Cancel()
			highlight:Destroy()
		end,
	}
end

return table.freeze(GuideArrow)

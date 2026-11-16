--!strict
-- Thin wrapper around Roblox's ProximityPrompt (concept 3.2, #90, ADR 0008). Features create
-- their station prompts here so keys, hold time, distance and texts come from Config.Ui.Prompts.
-- The prompt keeps Roblox's default style: it shows the key of the most recently used device
-- (keyboard key, gamepad button or a tap target) and switches when the player changes device,
-- so no custom glyphs are needed. Usable on server and client; stations create it on the server.

local CollectionService = game:GetService("CollectionService")

local Config = script.Parent:WaitForChild("Config")
local UiConfig = require(Config:WaitForChild("Ui")) :: any
local PromptSpec = require(script:WaitForChild("PromptSpec"))

export type Options = {
	-- Instance name, default "<preset>Prompt".
	name: string?,
	-- CollectionService tag, so the client can tell which station triggered.
	tag: string?,
}

local Prompts = {}

-- Creates a ProximityPrompt for `preset` under `parent` (a BasePart or Attachment).
function Prompts.create(preset: string, parent: Instance, options: Options?): ProximityPrompt
	local spec = PromptSpec.resolve(preset, UiConfig)
	local opts = options or {}
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = opts.name or `{preset}Prompt`
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.ActionText = spec.ActionText
	prompt.ObjectText = spec.ObjectText
	prompt.KeyboardKeyCode = (Enum.KeyCode :: any)[spec.KeyboardKeyCode]
	prompt.GamepadKeyCode = (Enum.KeyCode :: any)[spec.GamepadKeyCode]
	prompt.HoldDuration = spec.HoldDuration
	prompt.MaxActivationDistance = spec.MaxActivationDistance
	prompt.RequiresLineOfSight = spec.RequiresLineOfSight
	if opts.tag then
		CollectionService:AddTag(prompt, opts.tag)
	end
	prompt.Parent = parent
	return prompt
end

return table.freeze(Prompts)

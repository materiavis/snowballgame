--!strict
-- Resolves a prompt preset of Config.Ui.Prompts into ProximityPrompt property values (#90,
-- ADR 0008). Pure, so the presets are tested headless. A preset overrides Config.Ui.Prompts.Default
-- field by field; ActionText and ObjectText are keys in Config.Ui.Text. Anything invalid is an
-- error, so a broken preset fails where the feature creates its prompt.

export type Spec = {
	ActionText: string,
	ObjectText: string,
	KeyboardKeyCode: string,
	GamepadKeyCode: string,
	HoldDuration: number,
	MaxActivationDistance: number,
	RequiresLineOfSight: boolean,
}

local PromptSpec = {}

local function finiteAtLeast(value: any, minimum: number): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value >= minimum
end

local function text(ui: any, preset: string, field: string, key: any): string
	if key == nil then
		return ""
	end
	local value = if type(key) == "string" then ui.Text[key] else nil
	if type(value) ~= "string" then
		error(`Prompts: preset {preset} {field} '{tostring(key)}' is not a key in Config.Ui.Text`, 3)
	end
	return value
end

function PromptSpec.resolve(preset: string, ui: any): Spec
	local presets = ui.Prompts
	local base = presets.Default
	local own = presets[preset]
	if type(own) ~= "table" then
		error(`Prompts: unknown preset '{tostring(preset)}' (add it to Config.Ui.Prompts)`, 2)
	end
	local function pick(field: string): any
		local value = own[field]
		if value == nil then
			return base[field]
		end
		return value
	end

	local spec: Spec = {
		ActionText = text(ui, preset, "ActionText", pick("ActionText")),
		ObjectText = text(ui, preset, "ObjectText", pick("ObjectText")),
		KeyboardKeyCode = pick("KeyboardKeyCode"),
		GamepadKeyCode = pick("GamepadKeyCode"),
		HoldDuration = pick("HoldDuration"),
		MaxActivationDistance = pick("MaxActivationDistance"),
		RequiresLineOfSight = pick("RequiresLineOfSight"),
	}
	for _, field in { "KeyboardKeyCode", "GamepadKeyCode" } do
		local value = (spec :: any)[field]
		if type(value) ~= "string" or value == "" then
			error(`Prompts: preset {preset} {field} must be an Enum.KeyCode name`, 2)
		end
	end
	if not finiteAtLeast(spec.HoldDuration, 0) then
		error(`Prompts: preset {preset} HoldDuration must be a number >= 0`, 2)
	end
	if not finiteAtLeast(spec.MaxActivationDistance, 0) or spec.MaxActivationDistance == 0 then
		error(`Prompts: preset {preset} MaxActivationDistance must be a number > 0`, 2)
	end
	if type(spec.RequiresLineOfSight) ~= "boolean" then
		error(`Prompts: preset {preset} RequiresLineOfSight must be a boolean`, 2)
	end
	return table.freeze(spec)
end

return table.freeze(PromptSpec)

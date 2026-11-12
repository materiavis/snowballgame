--!strict
-- Config.Ui colours and fonts as Roblox values (ADR 0008). The config stays pure data so the
-- layout tests can load it; this is the one place that turns it into Color3 and Enum.Font.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Ui")) :: any

local function colour(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local Theme = {
	Config = UiConfig,
	Brand = colour(UiConfig.Colours.Brand),
	Surface = colour(UiConfig.Colours.Surface),
	SurfaceRaised = colour(UiConfig.Colours.SurfaceRaised),
	Text = colour(UiConfig.Colours.Text),
	TextMuted = colour(UiConfig.Colours.TextMuted),
	Max = colour(UiConfig.Colours.Max),
	FontRegular = (Enum.Font :: any)[UiConfig.Fonts.Regular] :: Enum.Font,
	FontBold = (Enum.Font :: any)[UiConfig.Fonts.Bold] :: Enum.Font,
}

return table.freeze(Theme)

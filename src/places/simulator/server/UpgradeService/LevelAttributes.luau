--!strict
-- Upgrade attributes on the Player (ADR 0010). Pure, so a headless spec can play a live server.
--
-- `Upgrade<Id>Level` is the HUD contract and is written on every server when the profile loads
-- and after every change. `Upgrade<Id>Effect` is playtest evidence, written only with
-- `diagnostics` (Studio at PlaceId 0). Clients only read these; a client-side write does not
-- replicate and the server never reads them back.

export type Options = {
	ids: { string },
	-- UpgradeCore.level: the level, or nil while not loaded / unusable.
	level: (userId: number, id: string) -> number?,
	effect: (id: string, level: number) -> number,
	-- UpgradeAttributes.level / .effect.
	levelName: (id: string) -> string,
	effectName: (id: string) -> string,
	diagnostics: boolean,
}

export type Mirror = {
	-- Writes every upgrade of one player. Call it only while the profile is loaded.
	mirror: (player: any, userId: number) -> (),
}

local LevelAttributes = {}

function LevelAttributes.new(options: Options): Mirror
	-- A level the profile cannot give (a broken stored value) removes its attribute, so the HUD
	-- shows "–" for that row instead of a stale level.
	local function mirror(player: any, userId: number)
		for _, id in options.ids do
			local level = options.level(userId, id)
			player:SetAttribute(options.levelName(id), level)
			if options.diagnostics then
				player:SetAttribute(options.effectName(id), if level ~= nil then options.effect(id, level) else nil)
			end
		end
	end

	return table.freeze({ mirror = mirror })
end

return table.freeze(LevelAttributes)

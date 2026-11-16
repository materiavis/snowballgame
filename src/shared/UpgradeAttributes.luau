--!strict
-- Player attribute names for upgrades (ADR 0010). Pure, shared by UpgradeService (writer) and
-- the Simulator HUD (reader), so both always agree on the names.
--   Upgrade<Id>Level   every server: the saved level 0..MaxLevel (the HUD contract)
--   Upgrade<Id>Effect  Studio at PlaceId 0 only: the effect at that level (playtest evidence)
--   UpgradeLastPurchase, UpgradeRefusals  Studio at PlaceId 0 only
-- <Id> is the Config.Upgrades id with a capital first letter ("walkSpeed" -> "WalkSpeed").

local UpgradeAttributes = {}

UpgradeAttributes.LAST_PURCHASE = "UpgradeLastPurchase"
UpgradeAttributes.REFUSALS = "UpgradeRefusals"

local function capitalised(id: string): string
	return string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
end

function UpgradeAttributes.level(id: string): string
	return `Upgrade{capitalised(id)}Level`
end

function UpgradeAttributes.effect(id: string): string
	return `Upgrade{capitalised(id)}Effect`
end

return table.freeze(UpgradeAttributes)

--!strict
-- Mirrors a loaded player's pets to player attributes (ADR 0013). Pure: the player is anything
-- with SetAttribute, the reads are injected, so a headless spec checks every write.
--
-- Every server: PetMultiplier (selling #38 reads it), PetSlots, PetInventorySize, PetInventory
-- (own pets window) and PetEquipped (followers on every client). Studio at PlaceId 0 adds
-- PetInventoryCount and PetEquippedUids. The client only reads them; server code never does.

export type Entry = { uid: string, kind: string, equipped: boolean }

export type Options = {
	multiplierName: string,
	-- Config.Pets.Attributes
	names: { Inventory: string, Equipped: string, Slots: string, InventorySize: string },
	entries: (userId: number) -> { Entry }?,
	multiplier: (userId: number) -> number,
	slots: (userId: number) -> number?,
	capacity: (userId: number) -> number?,
	count: (userId: number) -> number?,
	encodeInventory: (entries: { Entry }) -> string,
	encodeEquipped: (entries: { Entry }) -> string,
	diagnostics: boolean,
}

export type Attributes = {
	-- Writes everything for a loaded profile. Does nothing while the profile is not loaded, so
	-- the last published state stays until the next load.
	mirror: (player: any, userId: number) -> boolean,
}

local PetAttributes = {}

PetAttributes.COUNT = "PetInventoryCount"
PetAttributes.EQUIPPED_UIDS = "PetEquippedUids"

function PetAttributes.new(options: Options): Attributes
	local names = options.names

	local function mirror(player: any, userId: number): boolean
		local list = options.entries(userId)
		if list == nil then
			return false
		end
		local equipped: { Entry } = {}
		local uids: { string } = {}
		for _, entry in list do
			if entry.equipped then
				table.insert(equipped, entry)
				table.insert(uids, entry.uid)
			end
		end
		player:SetAttribute(options.multiplierName, options.multiplier(userId))
		player:SetAttribute(names.Slots, options.slots(userId))
		player:SetAttribute(names.InventorySize, options.capacity(userId))
		player:SetAttribute(names.Inventory, options.encodeInventory(list))
		player:SetAttribute(names.Equipped, options.encodeEquipped(equipped))
		if options.diagnostics then
			player:SetAttribute(PetAttributes.COUNT, options.count(userId))
			player:SetAttribute(PetAttributes.EQUIPPED_UIDS, table.concat(uids, ","))
		end
		return true
	end

	return table.freeze({ mirror = mirror })
end

return table.freeze(PetAttributes)

--!strict
-- Pet inventory rules (concept 7.9, ADR 0003 data model, ADR 0013). Pure: the catalogue, the
-- formulas, profile access and the uid maker are injected, so `lune run tests` runs it against
-- DataService's fake store.
--
-- Pets live in the profile as `sim.pets[uid] = { kind, variant, frosty, equipped }` (save format
-- v1). The uid is unique, so a duplicated pet is detectable (trading, #49). A client sends only a
-- uid and the wanted equip state; ownership, slots and the multiplier are decided here.

export type Entry = { uid: string, kind: string, equipped: boolean }

export type Event = {
	-- Added: a pet joined the inventory. Equipped / Unequipped: its state changed. Cleared: a
	-- Studio switch emptied the inventory. Refused: nothing changed.
	kind: "Added" | "Equipped" | "Unequipped" | "Cleared" | "Refused",
	userId: number,
	uid: string?,
	pet: string?,
	count: number?,
	reason: string,
	refusal: string?,
}

export type Catalogue = {
	isKind: (kind: any) -> boolean,
	bonusOf: (record: any) -> number?,
}

export type Formulas = {
	equipSlots: (highestZone: number, hasGamepass: boolean) -> number,
	totalMultiplier: (bonuses: { number }) -> number,
}

export type Deps = {
	catalogue: Catalogue,
	formulas: Formulas,
	-- Config.Data.InventorySize: used when the stored inventorySize is not a whole number >= 0.
	defaultInventorySize: number,
	-- Config.Net.Pets.MaxUidLength: a uid longer than this could not be sent back by the client.
	maxUidLength: number,
	-- The live profile table while loaded, else nil (DataService.GetProfile).
	getProfile: (userId: number) -> any,
	-- A new uid candidate. PetCore retries on a clash with the player's own pets.
	newUid: (userId: number) -> string,
	-- The +3 slots game pass (9.2). Always false until monetisation exists.
	hasSlotsPass: (userId: number) -> boolean,
	log: (level: "info" | "warn", message: string) -> (),
}

export type Core = {
	entries: (userId: number) -> { Entry }?,
	count: (userId: number) -> number?,
	capacity: (userId: number) -> number?,
	slots: (userId: number) -> number?,
	equipped: (userId: number) -> { Entry },
	multiplier: (userId: number) -> number,
	hasRoom: (userId: number) -> (boolean, string?),
	add: (userId: number, kind: any, reason: string) -> (boolean, string),
	setEquipped: (userId: number, uid: any, equipped: any, reason: string) -> (boolean, string?),
	clear: (userId: number, reason: string) -> (boolean, any),
	subscribe: (listener: (event: Event) -> ()) -> () -> (),
}

local NOT_LOADED = "NotLoaded"
local BAD_PROFILE = "BadProfile"
local BAD_KIND = "BadKind"
local BAD_UID = "BadUid"
local BAD_PET = "BadPet"
local BAD_STATE = "BadState"
local INVENTORY_FULL = "InventoryFull"
local SLOTS_FULL = "SlotsFull"
local UNCHANGED = "Unchanged"
local UID_CLASH = "UidClash"

-- How often add() asks for a new uid when the candidate is taken. A clash needs the same
-- second and the same 16-bit random number, so the second candidate practically always works.
local UID_ATTEMPTS = 8

local PetCore = {}

PetCore.Refusal = table.freeze({
	NotLoaded = NOT_LOADED,
	BadProfile = BAD_PROFILE,
	BadKind = BAD_KIND,
	BadUid = BAD_UID,
	BadPet = BAD_PET,
	BadState = BAD_STATE,
	InventoryFull = INVENTORY_FULL,
	SlotsFull = SLOTS_FULL,
	Unchanged = UNCHANGED,
	UidClash = UID_CLASH,
})

local function isWhole(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value % 1 == 0
end

function PetCore.new(deps: Deps): Core
	local catalogue = deps.catalogue
	local listeners: { (event: Event) -> () } = {}

	local function emit(event: Event)
		for _, listener in table.clone(listeners) do
			-- A failing listener must never undo or block a change.
			local ok, err = pcall(listener, event)
			if not ok then
				deps.log("warn", `listener error: {err}`)
			end
		end
	end

	local function refuse(userId: number, reason: string, refusal: string, uid: any?, pet: any?): (boolean, string)
		emit({
			kind = "Refused",
			userId = userId,
			uid = if type(uid) == "string" then uid else nil,
			pet = if type(pet) == "string" then pet else nil,
			reason = reason,
			refusal = refusal,
		})
		return false, refusal
	end

	-- The profile's sim table and pet map, or nil and NotLoaded / BadProfile.
	local function simOf(userId: number): (any, any, string?)
		local profile = deps.getProfile(userId)
		if profile == nil then
			return nil, nil, NOT_LOADED
		end
		local sim = profile.sim
		if type(sim) ~= "table" or type(sim.pets) ~= "table" then
			return nil, nil, BAD_PROFILE
		end
		return sim, sim.pets, nil
	end

	local function isValid(record: any): boolean
		return catalogue.bonusOf(record) ~= nil and (record.equipped == nil or type(record.equipped) == "boolean")
	end

	local function countOf(pets: any): number
		local count = 0
		for _ in pets do
			count += 1
		end
		return count
	end

	local function capacityOf(sim: any): number
		local stored = sim.inventorySize
		if isWhole(stored) and stored >= 0 then
			return stored
		end
		return deps.defaultInventorySize
	end

	local function slotsOf(userId: number, sim: any): number
		local highest = sim.highestZone
		if not (isWhole(highest) and highest >= 1) then
			highest = 1
		end
		return deps.formulas.equipSlots(highest, deps.hasSlotsPass(userId))
	end

	local function equippedCount(pets: any): number
		local count = 0
		for _, record in pets do
			if isValid(record) and record.equipped == true then
				count += 1
			end
		end
		return count
	end

	-- Valid pets with a uid the client can send back, sorted by uid so every server and every
	-- attribute write lists them in the same order.
	local function entries(userId: number): { Entry }?
		local _, pets = simOf(userId)
		if pets == nil then
			return nil
		end
		local list: { Entry } = {}
		for uid, record in pets do
			if type(uid) == "string" and #uid <= deps.maxUidLength and isValid(record) then
				table.insert(list, { uid = uid, kind = record.kind, equipped = record.equipped == true })
			end
		end
		table.sort(list, function(a: Entry, b: Entry): boolean
			return a.uid < b.uid
		end)
		return list
	end

	local function count(userId: number): number?
		local _, pets = simOf(userId)
		return if pets ~= nil then countOf(pets) else nil
	end

	local function capacity(userId: number): number?
		local sim = simOf(userId)
		return if sim ~= nil then capacityOf(sim) else nil
	end

	local function slots(userId: number): number?
		local sim = simOf(userId)
		return if sim ~= nil then slotsOf(userId, sim) else nil
	end

	local function equipped(userId: number): { Entry }
		local list = {}
		for _, entry in entries(userId) or {} do
			if entry.equipped then
				table.insert(list, entry)
			end
		end
		return list
	end

	-- Concept 7.9: total = 1 + bonus 1 + bonus 2 + ... of the equipped pets. If a profile holds
	-- more equipped pets than slots (slots can only grow in the Vertical Slice), only the
	-- strongest `slots` count, so a stored state can never exceed what the slots allow.
	local function multiplier(userId: number): number
		local sim, pets = simOf(userId)
		if sim == nil then
			return deps.formulas.totalMultiplier({})
		end
		local bonuses: { number } = {}
		for _, record in pets do
			if isValid(record) and record.equipped == true then
				table.insert(bonuses, catalogue.bonusOf(record) :: number)
			end
		end
		table.sort(bonuses, function(a: number, b: number): boolean
			return a > b
		end)
		local counted: { number } = {}
		for index = 1, math.min(#bonuses, slotsOf(userId, sim)) do
			counted[index] = bonuses[index]
		end
		return deps.formulas.totalMultiplier(counted)
	end

	local function hasRoom(userId: number): (boolean, string?)
		local sim, pets, why = simOf(userId)
		if sim == nil then
			return false, why
		end
		if countOf(pets) >= capacityOf(sim) then
			return false, INVENTORY_FULL
		end
		return true, nil
	end

	local function add(userId: number, kind: any, reason: string): (boolean, string)
		if not catalogue.isKind(kind) then
			return refuse(userId, reason, BAD_KIND, nil, kind)
		end
		local sim, pets, why = simOf(userId)
		if sim == nil then
			return refuse(userId, reason, why :: string, nil, kind)
		end
		if countOf(pets) >= capacityOf(sim) then
			return refuse(userId, reason, INVENTORY_FULL, nil, kind)
		end
		local uid: string? = nil
		for _ = 1, UID_ATTEMPTS do
			local candidate = deps.newUid(userId)
			if
				type(candidate) == "string"
				and #candidate <= deps.maxUidLength
				and string.match(candidate, "^[%w_%-]+$") ~= nil
				and pets[candidate] == nil
			then
				uid = candidate
				break
			end
		end
		if uid == nil then
			return refuse(userId, reason, UID_CLASH, nil, kind)
		end
		pets[uid] = { kind = kind, variant = "normal", frosty = false, equipped = false }
		emit({ kind = "Added", userId = userId, uid = uid, pet = kind, reason = reason })
		return true, uid
	end

	local function setEquipped(userId: number, uid: any, wanted: any, reason: string): (boolean, string?)
		if type(wanted) ~= "boolean" then
			return refuse(userId, reason, BAD_STATE, uid)
		end
		if type(uid) ~= "string" then
			return refuse(userId, reason, BAD_UID)
		end
		local sim, pets, why = simOf(userId)
		if sim == nil then
			return refuse(userId, reason, why :: string, uid)
		end
		local record = pets[uid]
		if record == nil then
			return refuse(userId, reason, BAD_UID, uid)
		end
		if not isValid(record) then
			return refuse(userId, reason, BAD_PET, uid)
		end
		if (record.equipped == true) == wanted then
			return refuse(userId, reason, UNCHANGED, uid, record.kind)
		end
		if wanted and equippedCount(pets) >= slotsOf(userId, sim) then
			return refuse(userId, reason, SLOTS_FULL, uid, record.kind)
		end
		record.equipped = wanted
		emit({
			kind = if wanted then "Equipped" else "Unequipped",
			userId = userId,
			uid = uid,
			pet = record.kind,
			reason = reason,
		})
		return true, nil
	end

	-- Studio switch only (PetClear): removes every pet of the player.
	local function clear(userId: number, reason: string): (boolean, any)
		local sim, pets, why = simOf(userId)
		if sim == nil then
			return refuse(userId, reason, why :: string)
		end
		local removed = countOf(pets)
		table.clear(pets)
		emit({ kind = "Cleared", userId = userId, count = removed, reason = reason })
		return true, removed
	end

	local function subscribe(listener: (event: Event) -> ()): () -> ()
		table.insert(listeners, listener)
		return function()
			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end
	end

	return table.freeze({
		entries = entries,
		count = count,
		capacity = capacity,
		slots = slots,
		equipped = equipped,
		multiplier = multiplier,
		hasRoom = hasRoom,
		add = add,
		setEquipped = setEquipped,
		clear = clear,
		subscribe = subscribe,
	})
end

return table.freeze(PetCore)

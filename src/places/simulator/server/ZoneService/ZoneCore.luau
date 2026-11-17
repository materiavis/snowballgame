--!strict
-- Zone rules (concept 7.6, 6.5, ADR 0009, ADR 0014). Pure: config, formulas, the map view,
-- profile access, the coin spend and the clock are injected, so `lune run tests` runs it against
-- DataService's fake store.
--
-- The profile holds `sim.unlockedZones` (set with string keys, zone 1 always unlocked),
-- `sim.lastZone` and `sim.highestZone` (save format v1, unchanged). A client sends only a zone
-- number. Price, cap, map, adjacency and the unlocked set are read and computed here.

export type ZonesConfig = {
	ZoneCount: number,
	HighestOpenZone: any,
	ZoneTeleportWait: number,
}
export type Formulas = {
	isZone: (value: any) -> boolean,
	worldOf: (zone: number) -> number,
	isWorldGate: (zone: number) -> boolean,
	barrierPrice: (zone: number) -> number,
}
-- What the map of this Place offers (ZoneMap). Read at call time.
export type MapView = {
	-- A valid zone area `zone` with exactly one ZoneStart (ADR 0009).
	hasZone: (zone: number) -> boolean,
	-- At least one bound Barrier station in zone area `zone`.
	hasBarrier: (zone: number) -> boolean,
}

export type Event = {
	-- Unlock: bought a zone. Teleport: zone teleport accepted. Enter: now counted in a zone.
	-- Reset: Studio switch reset the unlocks. Refused: nothing changed.
	kind: "Unlock" | "Teleport" | "Enter" | "Reset" | "Refused",
	action: "Unlock" | "Teleport" | "Enter" | "Reset",
	userId: number,
	zone: any,
	price: number?,
	reason: string,
	refusal: string?,
}

export type Deps = {
	config: ZonesConfig,
	formulas: Formulas,
	worldIndex: number,
	map: MapView,
	-- The live profile table while loaded, else nil (DataService.GetProfile).
	getProfile: (userId: number) -> any,
	-- CurrencyService.SpendCoins: true on success, else false and a refusal.
	spendCoins: (userId: number, amount: number, reason: string) -> (boolean, any),
	now: () -> number,
	log: (level: "info" | "warn", message: string) -> (),
}

export type Core = {
	capValid: () -> boolean,
	barrierState: (zone: number) -> (boolean, string?),
	unlocked: (userId: number) -> { number }?,
	isUnlocked: (userId: number, zone: number) -> boolean,
	purchase: (userId: number, zone: any, reason: string) -> (boolean, any),
	teleport: (userId: number, zone: any, reason: string) -> (boolean, any, number?),
	enter: (userId: number, zone: number, reason: string) -> (boolean, any),
	startZone: (userId: number) -> number?,
	current: (userId: number) -> number?,
	resetUnlocks: (userId: number, reason: string) -> (boolean, any),
	refuse: (userId: number, action: any, zone: any, reason: string, refusal: string) -> (boolean, string),
	forget: (userId: number) -> (),
	subscribe: (listener: (event: Event) -> ()) -> () -> (),
}

local ZoneCore = {}

ZoneCore.Refusal = table.freeze({
	BadZone = "BadZone", -- not a zone of this world that a barrier opens
	NotLoaded = "NotLoaded",
	BadProfile = "BadProfile",
	AlreadyUnlocked = "AlreadyUnlocked",
	NotAdjacent = "NotAdjacent", -- the zone before it is not unlocked
	WorldGate = "WorldGate", -- the end of a world: a world gate (#105), not a barrier
	NoCap = "NoCap", -- Config.Zones.HighestOpenZone missing or invalid
	Capped = "Capped", -- above Config.Zones.HighestOpenZone
	NotInMap = "NotInMap", -- no valid zone area with one ZoneStart in this Place
	NoBarrier = "NoBarrier", -- no bound barrier at the end of the zone before
	NotUnlocked = "NotUnlocked",
	NoStart = "NoStart",
	Wait = "Wait", -- within Config.Zones.ZoneTeleportWait after the last teleport
	Locked = "Locked", -- walked into a zone that is not unlocked
	NoCharacter = "NoCharacter",
})
local R = ZoneCore.Refusal

local FIRST_ZONE_KEY = "1"

function ZoneCore.new(deps: Deps): Core
	local config = deps.config
	local formulas = deps.formulas
	local listeners: { (event: Event) -> () } = {}
	local lastTeleport: { [number]: number } = {}
	local currentZone: { [number]: number } = {}

	local function emit(event: Event)
		for _, listener in table.clone(listeners) do
			-- A failing listener must never undo or block an unlock.
			local ok, err = pcall(listener, event)
			if not ok then
				deps.log("warn", `listener error: {err}`)
			end
		end
	end

	local function refuse(userId: number, action: any, zone: any, reason: string, refusal: string): (boolean, string)
		emit({ kind = "Refused", action = action, userId = userId, zone = zone, reason = reason, refusal = refusal })
		return false, refusal
	end

	local function inWorld(zone: any): boolean
		return formulas.isZone(zone) and formulas.worldOf(zone) == deps.worldIndex
	end

	local function capValid(): boolean
		return formulas.isZone(config.HighestOpenZone)
	end

	-- Whether the barrier at the end of `zone` can open in this Place: ADR 0009 (a) the next zone
	-- is in the map with one ZoneStart and (b) it is at most the cap. Same for every player.
	local function barrierState(zone: number): (boolean, string?)
		if not inWorld(zone) then
			return false, R.BadZone
		end
		if formulas.isWorldGate(zone) or zone >= config.ZoneCount then
			return false, R.WorldGate
		end
		if not capValid() then
			return false, R.NoCap
		end
		if zone + 1 > config.HighestOpenZone then
			return false, R.Capped
		end
		if not deps.map.hasZone(zone + 1) then
			return false, R.NotInMap
		end
		return true, nil
	end

	-- The profile's sim table and its unlocked zones as a set of numbers (zone 1 always in it).
	-- Malformed entries are ignored, never repaired here.
	local function readProfile(userId: number): (any, { [number]: boolean }?, string?)
		local profile = deps.getProfile(userId)
		if profile == nil then
			return nil, nil, R.NotLoaded
		end
		local sim = profile.sim
		if type(sim) ~= "table" or type(sim.unlockedZones) ~= "table" then
			return nil, nil, R.BadProfile
		end
		local set: { [number]: boolean } = { [1] = true }
		for key, value in sim.unlockedZones do
			local zone = if type(key) == "string" then tonumber(key) else nil
			if value == true and zone ~= nil and formulas.isZone(zone) then
				set[zone] = true
			end
		end
		return sim, set, nil
	end

	-- Unlocked zones of this world, ascending; nil while not loaded or broken.
	local function unlocked(userId: number): { number }?
		local _, set = readProfile(userId)
		if set == nil then
			return nil
		end
		local list: { number } = {}
		for zone in set do
			if inWorld(zone) then
				table.insert(list, zone)
			end
		end
		table.sort(list)
		return list
	end

	local function isUnlocked(userId: number, zone: number): boolean
		local _, set = readProfile(userId)
		return set ~= nil and set[zone] == true
	end

	-- Unlock `zone` through the barrier at the end of zone - 1.
	local function purchase(userId: number, zone: any, reason: string): (boolean, any)
		if not inWorld(zone) or not inWorld(zone - 1) then
			return refuse(userId, "Unlock", zone, reason, R.BadZone)
		end
		local sim, set, why = readProfile(userId)
		if sim == nil or set == nil then
			return refuse(userId, "Unlock", zone, reason, why :: string)
		end
		if set[zone] then
			-- A double tap lands here: the first request already wrote the unlock (6.5).
			return refuse(userId, "Unlock", zone, reason, R.AlreadyUnlocked)
		end
		local barrier = zone - 1
		if not set[barrier] then
			return refuse(userId, "Unlock", zone, reason, R.NotAdjacent)
		end
		local canOpen, closed = barrierState(barrier)
		if not canOpen then
			return refuse(userId, "Unlock", zone, reason, closed :: string)
		end
		if not deps.map.hasBarrier(barrier) then
			return refuse(userId, "Unlock", zone, reason, R.NoBarrier)
		end
		local price = formulas.barrierPrice(barrier)
		local spent, refusal = deps.spendCoins(userId, price, `Barrier:{zone}`)
		if not spent then
			emit({
				kind = "Refused",
				action = "Unlock",
				userId = userId,
				zone = zone,
				price = price,
				reason = reason,
				refusal = tostring(refusal),
			})
			return false, tostring(refusal)
		end
		-- No yield between the spend and these writes, so any save snapshot holds both or
		-- neither (DataService deep-copies when a write starts), as with upgrades (ADR 0010).
		sim.unlockedZones[tostring(zone)] = true
		if type(sim.highestZone) ~= "number" or sim.highestZone < zone then
			sim.highestZone = zone
		end
		emit({ kind = "Unlock", action = "Unlock", userId = userId, zone = zone, price = price, reason = reason })
		return true, zone
	end

	-- Zone teleport to the start of an unlocked zone. On success the wait starts now; the caller
	-- moves the character. Refused with Wait also returns the seconds left.
	local function teleport(userId: number, zone: any, reason: string): (boolean, any, number?)
		if not inWorld(zone) then
			return refuse(userId, "Teleport", zone, reason, R.BadZone)
		end
		local _, set, why = readProfile(userId)
		if set == nil then
			return refuse(userId, "Teleport", zone, reason, why :: string)
		end
		if not set[zone] then
			return refuse(userId, "Teleport", zone, reason, R.NotUnlocked)
		end
		if not deps.map.hasZone(zone) then
			return refuse(userId, "Teleport", zone, reason, R.NoStart)
		end
		local now = deps.now()
		local last = lastTeleport[userId]
		if last ~= nil and now - last < config.ZoneTeleportWait then
			refuse(userId, "Teleport", zone, reason, R.Wait)
			return false, R.Wait, config.ZoneTeleportWait - (now - last)
		end
		lastTeleport[userId] = now
		emit({ kind = "Teleport", action = "Teleport", userId = userId, zone = zone, reason = reason })
		return true, zone, nil
	end

	-- The player is now in zone area `zone`. Only an unlocked zone counts; it becomes the last
	-- visited zone (6.5: the next join starts there).
	local function enter(userId: number, zone: number, reason: string): (boolean, any)
		local sim, set, why = readProfile(userId)
		if sim == nil or set == nil then
			return false, why
		end
		if not set[zone] or not inWorld(zone) then
			return refuse(userId, "Enter", zone, reason, R.Locked)
		end
		sim.lastZone = zone
		if currentZone[userId] ~= zone then
			currentZone[userId] = zone
			emit({ kind = "Enter", action = "Enter", userId = userId, zone = zone, reason = reason })
		end
		return true, zone
	end

	-- Where a joining or respawning player starts: the last visited zone if it is still unlocked
	-- and has a start here, else the highest unlocked zone with a start, else nil (no zone
	-- areas: Roblox's spawn).
	local function startZone(userId: number): number?
		local sim, set = readProfile(userId)
		if sim == nil or set == nil then
			return nil
		end
		local last = sim.lastZone
		if inWorld(last) and set[last] and deps.map.hasZone(last) then
			return last
		end
		local best: number? = nil
		for zone in set do
			if inWorld(zone) and deps.map.hasZone(zone) and (best == nil or zone > best) then
				best = zone
			end
		end
		return best
	end

	-- Studio switch only (ZoneResetUnlocks): back to a new player's zones.
	local function resetUnlocks(userId: number, reason: string): (boolean, any)
		local sim, _, why = readProfile(userId)
		if sim == nil then
			return refuse(userId, "Reset", 1, reason, why :: string)
		end
		sim.unlockedZones = { [FIRST_ZONE_KEY] = true }
		sim.highestZone = 1
		sim.lastZone = 1
		emit({ kind = "Reset", action = "Reset", userId = userId, zone = 1, reason = reason })
		return true, 1
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
		capValid = capValid,
		barrierState = barrierState,
		unlocked = unlocked,
		isUnlocked = isUnlocked,
		purchase = purchase,
		teleport = teleport,
		enter = enter,
		startZone = startZone,
		current = function(userId: number): number?
			return currentZone[userId]
		end,
		resetUnlocks = resetUnlocks,
		refuse = refuse,
		forget = function(userId: number)
			lastTeleport[userId] = nil
			currentZone[userId] = nil
		end,
		subscribe = subscribe,
	})
end

return table.freeze(ZoneCore)

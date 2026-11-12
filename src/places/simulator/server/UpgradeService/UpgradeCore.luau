--!strict
-- Upgrade rules (concept 7.8, ADR 0010). Pure: config, formulas, profile access and the coin
-- spend are injected, so `lune run tests` runs it against DataService's fake store.
--
-- The level lives in the profile (`sim.upgrades[id]`, save format v1). The client sends only an
-- upgrade id. Level, price and maximum are read and computed here, never taken from a caller.

export type Definition = { BasePrice: number, Factor: number, Start: number, End: number }
export type Config = {
	MaxLevel: number,
	Order: { string },
	Definitions: { [string]: Definition },
	-- Ids that are shown but cannot be bought yet (owner decision 2026-11-12).
	Locked: { [string]: boolean }?,
}
export type Formulas = {
	cost: (id: string, level: number) -> number,
	effect: (id: string, level: number) -> number,
}

export type Event = {
	-- Purchase: bought one level. Set: a Studio switch set the level. Refused: nothing changed.
	kind: "Purchase" | "Set" | "Refused",
	userId: number,
	upgrade: any,
	from: number?,
	to: number?,
	price: number?,
	reason: string,
	refusal: string?,
}

export type Deps = {
	config: Config,
	formulas: Formulas,
	-- The live profile table while loaded, else nil (DataService.GetProfile).
	getProfile: (userId: number) -> any,
	-- CurrencyService.SpendCoins: true on success, else false and a refusal.
	spendCoins: (userId: number, amount: number, reason: string) -> (boolean, any),
	log: (level: "info" | "warn", message: string) -> (),
}

export type Core = {
	ids: () -> { string },
	isUpgrade: (id: any) -> boolean,
	isLocked: (id: string) -> boolean,
	level: (userId: number, id: string) -> (number?, string?),
	levelOrZero: (userId: number, id: string) -> number,
	nextPrice: (userId: number, id: string) -> number?,
	purchase: (userId: number, id: any, reason: string) -> (boolean, any),
	setLevel: (userId: number, id: any, level: any, reason: string) -> (boolean, any),
	subscribe: (listener: (event: Event) -> ()) -> () -> (),
}

-- Refusals besides the currency ones ("Insufficient", "NotLoaded", ...), which pass through.
local BAD_ID = "BadId"
local BAD_LEVEL = "BadLevel"
local BAD_PROFILE = "BadProfile"
local NOT_LOADED = "NotLoaded"
local MAX_LEVEL = "MaxLevel"
local LOCKED = "Locked"

local UpgradeCore = {}

UpgradeCore.Refusal = table.freeze({
	BadId = BAD_ID,
	BadLevel = BAD_LEVEL,
	BadProfile = BAD_PROFILE,
	NotLoaded = NOT_LOADED,
	MaxLevel = MAX_LEVEL,
	Locked = LOCKED,
})

-- "<id> <level>" from the UpgradeSetLevel switch. Returns the id and the level as typed (a
-- number if it parses), so a bad level still goes through setLevel's checks and is refused there.
function UpgradeCore.parseSetLevel(text: any): (string?, any)
	if type(text) ~= "string" then
		return nil, nil
	end
	local id, level = string.match(text, "^%s*(%S+)%s+(%S+)%s*$")
	if id == nil then
		return nil, nil
	end
	return id, tonumber(level) or level
end

function UpgradeCore.new(deps: Deps): Core
	local config = deps.config
	local listeners: { (event: Event) -> () } = {}

	local function emit(event: Event)
		for _, listener in table.clone(listeners) do
			-- A failing listener must never undo or block a purchase.
			local ok, err = pcall(listener, event)
			if not ok then
				deps.log("warn", `listener error: {err}`)
			end
		end
	end

	local function refuse(
		userId: number,
		id: any,
		reason: string,
		refusal: string,
		extra: { [string]: any }?
	): (boolean, string)
		local event: Event = { kind = "Refused", userId = userId, upgrade = id, reason = reason, refusal = refusal }
		if extra then
			event.from = extra.from
			event.price = extra.price
		end
		emit(event)
		return false, refusal
	end

	local function isUpgrade(id: any): boolean
		return type(id) == "string" and config.Definitions[id] ~= nil
	end

	local function isLocked(id: string): boolean
		local locked = config.Locked
		return locked ~= nil and locked[id] == true
	end

	local function isLevel(value: any): boolean
		return type(value) == "number" and value == value and value % 1 == 0 and value >= 0 and value <= config.MaxLevel
	end

	-- The profile's upgrade table, or nil and NotLoaded / BadProfile.
	local function upgradesOf(userId: number): (any, string?)
		local profile = deps.getProfile(userId)
		if profile == nil then
			return nil, NOT_LOADED
		end
		local sim = profile.sim
		if type(sim) ~= "table" or type(sim.upgrades) ~= "table" then
			return nil, BAD_PROFILE
		end
		return sim.upgrades, nil
	end

	local function level(userId: number, id: string): (number?, string?)
		if not isUpgrade(id) then
			return nil, BAD_ID
		end
		local upgrades, why = upgradesOf(userId)
		if upgrades == nil then
			return nil, why
		end
		local stored = upgrades[id]
		if not isLevel(stored) then
			return nil, BAD_PROFILE
		end
		return stored, nil
	end

	-- For effect consumers (ball growth, walk speed): level 0 while not loaded, so nothing is
	-- better than unupgraded before the profile is there. Unknown ids are a programming error.
	local function levelOrZero(userId: number, id: string): number
		if not isUpgrade(id) then
			error(`UpgradeCore: unknown upgrade {tostring(id)}`, 2)
		end
		return (level(userId, id)) or 0
	end

	local function nextPrice(userId: number, id: string): number?
		local current = level(userId, id)
		if current == nil or current >= config.MaxLevel then
			return nil
		end
		return deps.formulas.cost(id, current + 1)
	end

	local function purchase(userId: number, id: any, reason: string): (boolean, any)
		if not isUpgrade(id) then
			return refuse(userId, id, reason, BAD_ID)
		end
		-- Before the profile is read and long before any coins are spent.
		if isLocked(id) then
			return refuse(userId, id, reason, LOCKED)
		end
		local upgrades, why = upgradesOf(userId)
		if upgrades == nil then
			return refuse(userId, id, reason, why :: string)
		end
		local current = upgrades[id]
		if not isLevel(current) then
			return refuse(userId, id, reason, BAD_PROFILE)
		end
		if current >= config.MaxLevel then
			return refuse(userId, id, reason, MAX_LEVEL, { from = current })
		end
		local price = deps.formulas.cost(id, current + 1)
		local spent, refusal = deps.spendCoins(userId, price, `Upgrade:{id}`)
		if not spent then
			return refuse(userId, id, reason, tostring(refusal), { from = current, price = price })
		end
		-- No yield between the spend and this write, so a save snapshot holds both or neither
		-- (ADR 0010). The spend already proved the profile is loaded and the coins were there.
		upgrades[id] = current + 1
		emit({
			kind = "Purchase",
			userId = userId,
			upgrade = id,
			from = current,
			to = current + 1,
			price = price,
			reason = reason,
		})
		return true, current + 1
	end

	-- Studio switch only (UpgradeSetLevel): sets a level without coins, with the same id, level
	-- and profile checks as a purchase. Locked upgrades may be set (ADR 0010): that is how a
	-- playtest checks their saving and the GetLevel/GetEffect seam for #38/#40.
	local function setLevel(userId: number, id: any, target: any, reason: string): (boolean, any)
		if not isUpgrade(id) then
			return refuse(userId, id, reason, BAD_ID)
		end
		if not isLevel(target) then
			return refuse(userId, id, reason, BAD_LEVEL)
		end
		local upgrades, why = upgradesOf(userId)
		if upgrades == nil then
			return refuse(userId, id, reason, why :: string)
		end
		local current = upgrades[id]
		upgrades[id] = target
		emit({
			kind = "Set",
			userId = userId,
			upgrade = id,
			from = if isLevel(current) then current else nil,
			to = target,
			reason = reason,
		})
		return true, target
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
		ids = function(): { string }
			return config.Order
		end,
		isUpgrade = isUpgrade,
		isLocked = isLocked,
		level = level,
		levelOrZero = levelOrZero,
		nextPrice = nextPrice,
		purchase = purchase,
		setLevel = setLevel,
		subscribe = subscribe,
	})
end

return table.freeze(UpgradeCore)

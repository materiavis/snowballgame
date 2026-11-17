--!strict
-- Egg purchase and hatch rules (concept 7.9, 6.5, ADR 0013). Pure: config, catalogue, formulas,
-- odds, the generator, the clock, the coin spend and the pet inventory are injected, so
-- `lune run tests` runs it against DataService's fake store.
--
-- The client says only "hatch here"; the egg comes from the station the server found, the price
-- from Formulas.Pets.eggPrice, the rarity from the server's own roll. Nothing from the client is
-- used. Frosty and the luck boost are not rolled in this slice (#103).

export type Event = {
	-- Hatched: coins spent and a pet added. Refused: nothing changed.
	kind: "Hatched" | "Refused",
	userId: number,
	egg: number?,
	rarity: string?,
	pet: string?,
	uid: string?,
	price: number?,
	forced: boolean?,
	reason: string,
	refusal: string?,
}

export type Entry = { id: string, weight: number }

export type Deps = {
	-- Config.Eggs
	config: { HatchCooldownSeconds: number },
	catalogue: {
		isAvailable: (egg: any) -> boolean,
		petFor: (egg: number, rarity: string) -> string?,
	},
	eggCount: number,
	eggPrice: (egg: number) -> number,
	eggOdds: (egg: number, luck: boolean) -> { Entry },
	pick: (entries: { Entry }, roll: number) -> string,
	generator: { next: () -> number },
	-- Seconds, monotonic (os.clock on the server).
	now: () -> number,
	-- Studio switch EggForceRarity: a rarity id, or nil for a normal roll.
	forcedRarity: () -> string?,
	-- PetService.HasRoom / AddPet: true, or false and a refusal (NotLoaded, InventoryFull, ...).
	hasRoom: (userId: number) -> (boolean, string?),
	addPet: (userId: number, kind: string, reason: string) -> (boolean, string),
	-- CurrencyService.SpendCoins: true on success, else false and a refusal.
	spendCoins: (userId: number, amount: number, reason: string) -> (boolean, any),
	log: (level: "info" | "warn", message: string) -> (),
}

export type Core = {
	purchase: (userId: number, egg: any, reason: string) -> (boolean, any),
	-- Records a refusal decided outside the core (no station near the player).
	refuse: (userId: number, reason: string, refusal: string) -> (boolean, string),
	forget: (userId: number) -> (),
	subscribe: (listener: (event: Event) -> ()) -> () -> (),
}

local BAD_EGG = "BadEgg"
local NOT_AVAILABLE = "NotAvailable"
local BUSY = "Busy"
local NO_PET = "NoPet"
local ADD_FAILED = "AddFailed"

local EggCore = {}

EggCore.Refusal = table.freeze({
	BadEgg = BAD_EGG,
	NotAvailable = NOT_AVAILABLE,
	Busy = BUSY,
	NoPet = NO_PET,
	AddFailed = ADD_FAILED,
	-- Decided by the service, recorded through refuse(): no open station within reach.
	NoStation = "NoStation",
})

function EggCore.new(deps: Deps): Core
	local listeners: { (event: Event) -> () } = {}
	local lastHatch: { [number]: number } = {}

	local function emit(event: Event)
		for _, listener in table.clone(listeners) do
			-- A failing listener must never undo or block a hatch.
			local ok, err = pcall(listener, event)
			if not ok then
				deps.log("warn", `listener error: {err}`)
			end
		end
	end

	local function refuse(userId: number, reason: string, refusal: string, extra: { [string]: any }?): (boolean, string)
		local event: Event = { kind = "Refused", userId = userId, reason = reason, refusal = refusal }
		if extra then
			event.egg = extra.egg
			event.price = extra.price
		end
		emit(event)
		return false, refusal
	end

	local function isEgg(egg: any): boolean
		return type(egg) == "number" and egg == egg and egg % 1 == 0 and egg >= 1 and egg <= deps.eggCount
	end

	local function roll(egg: number): (string, boolean)
		local forced = deps.forcedRarity()
		if forced ~= nil and deps.catalogue.petFor(egg, forced) ~= nil then
			return forced, true
		end
		-- One roll for the rarity. #103 switches to Rng.rollEgg for the Frosty roll and the luck boost.
		return deps.pick(deps.eggOdds(egg, false), deps.generator.next()), false
	end

	local function purchase(userId: number, egg: any, reason: string): (boolean, any)
		if not isEgg(egg) then
			return refuse(userId, reason, BAD_EGG)
		end
		if not deps.catalogue.isAvailable(egg) then
			return refuse(userId, reason, NOT_AVAILABLE, { egg = egg })
		end
		-- Concept 6.5: a double tap is one purchase. Checked before anything is read or spent.
		local last = lastHatch[userId]
		if last ~= nil and deps.now() - last < deps.config.HatchCooldownSeconds then
			return refuse(userId, reason, BUSY, { egg = egg })
		end
		local room, why = deps.hasRoom(userId)
		if not room then
			return refuse(userId, reason, tostring(why), { egg = egg })
		end
		-- The roll and the pet are settled before any coin is spent, so nothing after the spend
		-- can fail on its own.
		local rarity, forced = roll(egg)
		local kind = deps.catalogue.petFor(egg, rarity)
		if kind == nil then
			return refuse(userId, reason, NO_PET, { egg = egg })
		end
		local price = deps.eggPrice(egg)
		local spent, refusal = deps.spendCoins(userId, price, `Egg:{egg}`)
		if not spent then
			return refuse(userId, reason, tostring(refusal), { egg = egg, price = price })
		end
		-- No yield between the spend and this add, so a save snapshot holds both or neither.
		local added, uid = deps.addPet(userId, kind, `Egg:{egg}`)
		if not added then
			-- Cannot happen after hasRoom in the same thread; logged loudly if it ever does.
			deps.log("warn", `user {userId} paid {price} for egg {egg} but the pet was refused: {uid}`)
			return refuse(userId, reason, ADD_FAILED, { egg = egg, price = price })
		end
		lastHatch[userId] = deps.now()
		emit({
			kind = "Hatched",
			userId = userId,
			egg = egg,
			rarity = rarity,
			pet = kind,
			uid = uid,
			price = price,
			forced = forced,
			reason = reason,
		})
		return true, uid
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
		purchase = purchase,
		refuse = function(userId: number, reason: string, refusal: string): (boolean, string)
			return refuse(userId, reason, refusal)
		end,
		forget = function(userId: number)
			lastHatch[userId] = nil
		end,
		subscribe = subscribe,
	})
end

return table.freeze(EggCore)

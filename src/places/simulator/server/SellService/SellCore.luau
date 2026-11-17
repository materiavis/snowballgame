--!strict
-- The sale decision (concept 7.5, 8.3, ADR 0012). Pure: the profile, the ball, the upgrade,
-- the pet multiplier, the bonus flags and the coin add are injected, so headless specs run it
-- against the real formulas, the real CurrencyCore and the fake store.
--
-- Coins = Formulas.Economy.saleCoins of (size in metres, finds in the ball, pets, rebirth,
-- Sell value upgrade, bonuses). Every factor comes from the server: the size from BallService,
-- the finds from this core (#40 adds them), pets from the server-written PetMultiplier
-- attribute (#41), rebirths from the profile, the upgrade from UpgradeService and the bonuses
-- from the server's flag source. No value comes from a client.
--
-- One sale per visit: `step` sells when the ball touches a plate with its owner at it, then
-- latches until the ball has left every plate (ADR 0012).

export type Flags = { [string]: boolean }

-- Studio-only replacement of single factors for the AC1 bonus test (SellFactorOverride).
export type Override = {
	pet: number?,
	rebirths: number?,
	flags: Flags?,
}

-- What the server sees of one ball in one check.
export type Contact = {
	touching: boolean, -- touches a scale plate
	clear: boolean, -- far enough from every plate to count as having left
	held: boolean, -- the owner's living character is at the ball (growth range, 7.4)
	zone: number?, -- ZoneIndex of the touched plate
}

export type Sale = {
	userId: number,
	zone: number?,
	sizeMetres: number,
	ballValue: number,
	findsValue: number,
	petMultiplier: number,
	rebirths: number,
	rebirthMultiplier: number,
	sellValueLevel: number,
	sellMultiplier: number,
	flags: Flags,
	bonus: number,
	coins: number,
	balance: number?,
}

export type Event = {
	kind: "Sale" | "Refused",
	userId: number,
	refusal: string?,
	-- The factors as far as they were computed (nil for NotLoaded and NoBall).
	sale: Sale?,
}

export type Deps = {
	economy: any, -- Formulas.Economy: saleCoins, sellBonus, rebirthMultiplier
	ballValue: (sizeMetres: number) -> number, -- Formulas.Zones.ballValue
	config: any, -- Config.Sell
	getProfile: (userId: number) -> any,
	sizeMetres: (userId: number) -> number?,
	resetBall: (userId: number) -> boolean,
	petMultiplier: (userId: number) -> any, -- raw attribute value
	sellValueLevel: (userId: number) -> number,
	sellMultiplier: (userId: number) -> number,
	bonusFlags: (userId: number) -> Flags,
	addCoins: (userId: number, amount: number, reason: string) -> (boolean, any),
	log: (level: "info" | "warn", message: string) -> (),
}

export type Core = {
	quote: (userId: number, zone: number?) -> (Sale?, string?),
	sell: (userId: number, zone: number?) -> (boolean, any),
	step: (userId: number, contact: Contact) -> (boolean, any),
	isLatched: (userId: number) -> boolean,
	addFindValue: (userId: number, value: any) -> (boolean, string?),
	findsValue: (userId: number) -> number,
	forget: (userId: number) -> (),
	setOverride: (override: Override?) -> (),
	subscribe: (listener: (event: Event) -> ()) -> () -> (),
}

local SellCore = {}

SellCore.Refusal = table.freeze({
	NotLoaded = "NotLoaded",
	NoBall = "NoBall",
	BadProfile = "BadProfile",
	TooSmall = "TooSmall",
	BadValue = "BadValue",
	TooLarge = "TooLarge",
	-- step() only: nothing was attempted.
	Latched = "Latched",
	NotTouching = "NotTouching",
	NotHeld = "NotHeld",
})

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The pet multiplier the sale uses: the attribute when it is a finite number >= 1, else 1.
function SellCore.petMultiplierOf(raw: any): number
	if isFinite(raw) and raw >= 1 then
		return raw
	end
	return 1
end

local function isRebirths(value: any): boolean
	return isFinite(value) and value >= 0 and value % 1 == 0
end

function SellCore.new(deps: Deps): Core
	local config = deps.config
	local finds: { [number]: number } = {}
	local latches: { [number]: boolean } = {}
	local listeners: { (event: Event) -> () } = {}
	local override: Override? = nil

	local function emit(event: Event)
		for _, listener in table.clone(listeners) do
			local ok, message = pcall(listener, event)
			if not ok then
				deps.log("warn", `sale listener failed: {tostring(message)}`)
			end
		end
	end

	local function refuse(userId: number, refusal: string, sale: Sale?): (boolean, string)
		emit({ kind = "Refused", userId = userId, refusal = refusal, sale = sale })
		return false, refusal
	end

	local function findsValue(userId: number): number
		return finds[userId] or 0
	end

	-- Every factor and the coins, without changing anything.
	local function quote(userId: number, zone: number?): (Sale?, string?)
		local profile = deps.getProfile(userId)
		if profile == nil then
			return nil, SellCore.Refusal.NotLoaded
		end
		local size = deps.sizeMetres(userId)
		if not isFinite(size) or (size :: number) < 0 then
			return nil, SellCore.Refusal.NoBall
		end
		local sim = profile.sim
		if type(sim) ~= "table" then
			return nil, SellCore.Refusal.BadProfile
		end
		local active = override
		local rebirths = if active and active.rebirths ~= nil then active.rebirths else sim.rebirths
		if not isRebirths(rebirths) then
			return nil, SellCore.Refusal.BadProfile
		end
		local pet = if active and active.pet ~= nil
			then active.pet
			else SellCore.petMultiplierOf(deps.petMultiplier(userId))
		local flags = if active and active.flags ~= nil then active.flags else deps.bonusFlags(userId)
		local input = {
			size = size :: number,
			findsValue = findsValue(userId),
			petMultiplier = pet,
			rebirthMultiplier = deps.economy.rebirthMultiplier(rebirths),
			sellMultiplier = deps.sellMultiplier(userId),
			bonus = deps.economy.sellBonus(flags),
		}
		local sale: Sale = {
			userId = userId,
			zone = zone,
			sizeMetres = input.size,
			ballValue = deps.ballValue(input.size),
			findsValue = input.findsValue,
			petMultiplier = input.petMultiplier,
			rebirths = rebirths,
			rebirthMultiplier = input.rebirthMultiplier,
			sellValueLevel = deps.sellValueLevel(userId),
			sellMultiplier = input.sellMultiplier,
			flags = flags,
			bonus = input.bonus,
			coins = deps.economy.saleCoins(input),
			balance = nil,
		}
		return sale, nil
	end

	-- Coins first; only a sale CurrencyService accepted empties the finds and resets the ball.
	-- No yield between the three, so a save snapshot holds the coins together with the reset.
	local function sell(userId: number, zone: number?): (boolean, any)
		local sale, refusal = quote(userId, zone)
		if sale == nil then
			return refuse(userId, refusal :: string, nil)
		end
		if sale.coins < config.MinSaleCoins then
			return refuse(userId, SellCore.Refusal.TooSmall, sale)
		end
		local ok, result = deps.addCoins(userId, sale.coins, config.CoinReason)
		if not ok then
			return refuse(userId, tostring(result), sale)
		end
		sale.balance = if type(result) == "number" then result else nil
		finds[userId] = nil
		if not deps.resetBall(userId) then
			deps.log("warn", `user {userId}: sold for {sale.coins} but the ball could not be reset`)
		end
		emit({ kind = "Sale", userId = userId, sale = sale })
		return true, sale
	end

	local function step(userId: number, contact: Contact): (boolean, any)
		if latches[userId] then
			if contact.clear then
				latches[userId] = nil
			end
			return false, SellCore.Refusal.Latched
		end
		if not contact.touching then
			return false, SellCore.Refusal.NotTouching
		end
		if not contact.held then
			return false, SellCore.Refusal.NotHeld
		end
		-- Latched for a refusal as well, so a refused ball is not retried every check.
		latches[userId] = true
		return sell(userId, contact.zone)
	end

	-- For finds (#40): adds the value of a find to the player's current ball. Emptied by a sale
	-- and when the player leaves (6.5: finds in the ball are lost on leaving).
	local function addFindValue(userId: number, value: any): (boolean, string?)
		if not isFinite(value) or value < 0 then
			return false, SellCore.Refusal.BadValue
		end
		local total = findsValue(userId) + value
		if total > config.MaxFindsValue then
			return false, SellCore.Refusal.TooLarge
		end
		finds[userId] = total
		return true, nil
	end

	return table.freeze({
		quote = quote,
		sell = sell,
		step = step,
		isLatched = function(userId: number): boolean
			return latches[userId] == true
		end,
		addFindValue = addFindValue,
		findsValue = findsValue,
		forget = function(userId: number)
			finds[userId] = nil
			latches[userId] = nil
		end,
		setOverride = function(value: Override?)
			override = value
		end,
		subscribe = function(listener: (event: Event) -> ()): () -> ()
			table.insert(listeners, listener)
			return function()
				local index = table.find(listeners, listener)
				if index then
					table.remove(listeners, index)
				end
			end
		end,
	})
end

return table.freeze(SellCore)

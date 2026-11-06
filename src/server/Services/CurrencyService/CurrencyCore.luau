--!strict
-- Balance changes for any number of currencies (ADR 0007). Pure and game-agnostic: the
-- currencies (profile path, total path, bounds) come from config, profiles from an injected
-- getProfile, so `lune run tests` drives it against DataCore and the fake store.
--
-- Rules for every change:
--   * the profile must be loaded (getProfile returns it); otherwise nothing changes,
--   * the amount is a finite whole number >= 0 and at most the currency's MaxChange,
--   * spending more than the balance is refused, so a balance never goes below 0,
--   * a balance never goes above MaxBalance (the rest is dropped and logged),
--   * the total (if the currency has one) only grows: spends and resets leave it alone.
-- Nothing here saves. The profile is changed in place and DataService stores it with the next
-- autosave, or at once when the caller asks DataService.SaveNow.

export type CurrencyConfig = {
	Path: { string },
	TotalPath: { string }?,
	MaxChange: number,
	MaxBalance: number,
}

export type Config = {
	Currencies: { [string]: CurrencyConfig },
	MaxReasonLength: number,
}

export type Refusal =
	"UnknownCurrency"
	| "BadAmount"
	| "TooLarge"
	| "BadReason"
	| "NotLoaded"
	| "BadProfile"
	| "Insufficient"

export type Operation = "Add" | "Spend" | "Reset"

-- Earn/Spend/Reset are economy events (analytics hook, #43). Refused is for logs and Studio.
export type Event = {
	kind: "Earn" | "Spend" | "Reset" | "Refused",
	operation: Operation, -- what was asked for; differs from kind only when Refused
	userId: number,
	currency: string,
	amount: number, -- requested amount (for Reset: the balance that was cleared)
	balance: number?, -- balance after the change; nil if the profile was not readable
	total: number?, -- total earned after the change, for currencies with a total
	reason: string,
	refusal: Refusal?,
	clamped: number?, -- Earn only: amount dropped at MaxBalance
}

export type Deps = {
	config: Config,
	getProfile: (userId: number) -> any, -- live profile table, or nil unless loaded
	log: (level: "info" | "warn", message: string) -> (),
}

local CurrencyCore = {}

local function readPath(profile: any, path: { string }): (any, string?)
	local node = profile
	for index = 1, #path - 1 do
		node = node[path[index]]
		if type(node) ~= "table" then
			return nil, nil
		end
	end
	return node, path[#path]
end

-- A stored balance the service can use: finite, whole, >= 0.
local function isBalance(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge and value % 1 == 0
end

function CurrencyCore.new(deps: Deps)
	local config = deps.config
	local listeners: { (event: Event) -> () } = {}
	local core = {}

	local function emit(event: Event)
		for _, listener in table.clone(listeners) do
			-- A failing listener (e.g. analytics) must never undo or block a balance change.
			local ok, err = pcall(listener, event)
			if not ok then
				deps.log("warn", `listener error: {err}`)
			end
		end
	end

	local function refuse(
		operation: Operation,
		userId: number,
		currency: string,
		amount: any,
		reason: any,
		refusal: Refusal,
		balance: number?
	)
		emit({
			kind = "Refused",
			operation = operation,
			userId = userId,
			currency = currency,
			amount = if type(amount) == "number" then amount else 0,
			balance = balance,
			reason = if type(reason) == "string" then reason else tostring(reason),
			refusal = refusal,
		})
		return false, refusal
	end

	-- Shared checks. Returns the currency config, the balance's table and key and the total's
	-- table and key, or refuses.
	local function prepare(
		operation: Operation,
		userId: number,
		currency: string,
		amount: any,
		reason: any
	): (boolean, any, any, any, any, any)
		local def = config.Currencies[currency]
		if def == nil then
			return refuse(operation, userId, tostring(currency), amount, reason, "UnknownCurrency")
		end
		if type(reason) ~= "string" or reason == "" or #reason > config.MaxReasonLength then
			return refuse(operation, userId, currency, amount, reason, "BadReason")
		end
		if not isBalance(amount) then
			return refuse(operation, userId, currency, amount, reason, "BadAmount")
		end
		if amount > def.MaxChange then
			return refuse(operation, userId, currency, amount, reason, "TooLarge")
		end
		local profile = deps.getProfile(userId)
		if type(profile) ~= "table" then
			return refuse(operation, userId, currency, amount, reason, "NotLoaded")
		end
		local node, key = readPath(profile, def.Path)
		if node == nil or not isBalance(node[key]) then
			return refuse(operation, userId, currency, amount, reason, "BadProfile")
		end
		local totalNode, totalKey = nil, nil
		if def.TotalPath then
			totalNode, totalKey = readPath(profile, def.TotalPath)
			if totalNode == nil or not isBalance(totalNode[totalKey]) then
				return refuse(operation, userId, currency, amount, reason, "BadProfile", node[key])
			end
		end
		return true, def, node, key, totalNode, totalKey
	end

	-- Adds `amount` and grows the total by the same. Returns true and the new balance.
	function core.add(userId: number, currency: string, amount: number, reason: string): (boolean, any)
		local ok, def, node, key, totalNode, totalKey = prepare("Add", userId, currency, amount, reason)
		if not ok then
			return false, def
		end
		if amount == 0 then
			return true, node[key]
		end
		local before = node[key]
		local after = math.min(before + amount, def.MaxBalance)
		node[key] = after
		local total = nil
		if totalNode then
			total = math.min(totalNode[totalKey] + amount, def.MaxBalance)
			totalNode[totalKey] = total
		end
		local clamped = before + amount - after
		if clamped > 0 then
			deps.log("warn", `{userId} {currency} held at MaxBalance, {clamped} dropped ({reason})`)
		end
		emit({
			kind = "Earn",
			operation = "Add",
			userId = userId,
			currency = currency,
			amount = amount,
			balance = after,
			total = total,
			reason = reason,
			clamped = if clamped > 0 then clamped else nil,
		})
		return true, after
	end

	-- Takes `amount` if the balance covers it; otherwise changes nothing.
	function core.spend(userId: number, currency: string, amount: number, reason: string): (boolean, any)
		local ok, def, node, key, totalNode, totalKey = prepare("Spend", userId, currency, amount, reason)
		if not ok then
			return false, def
		end
		local before = node[key]
		if amount > before then
			return refuse("Spend", userId, currency, amount, reason, "Insufficient", before)
		end
		if amount == 0 then
			return true, before
		end
		node[key] = before - amount
		emit({
			kind = "Spend",
			operation = "Spend",
			userId = userId,
			currency = currency,
			amount = amount,
			balance = node[key],
			total = if totalNode then totalNode[totalKey] else nil,
			reason = reason,
		})
		return true, node[key]
	end

	-- Sets the balance to 0 (a rebirth resets coins, concept 7.10). The total stays.
	function core.reset(userId: number, currency: string, reason: string): (boolean, any)
		local ok, def, node, key, totalNode, totalKey = prepare("Reset", userId, currency, 0, reason)
		if not ok then
			return false, def
		end
		local before = node[key]
		node[key] = 0
		emit({
			kind = "Reset",
			operation = "Reset",
			userId = userId,
			currency = currency,
			amount = before,
			balance = 0,
			total = if totalNode then totalNode[totalKey] else nil,
			reason = reason,
		})
		return true, 0
	end

	-- Balance, or nil if the profile is not loaded or the currency is unknown.
	function core.get(userId: number, currency: string): number?
		local def = config.Currencies[currency]
		local profile = deps.getProfile(userId)
		if def == nil or type(profile) ~= "table" then
			return nil
		end
		local node, key = readPath(profile, def.Path)
		return if node and isBalance(node[key]) then node[key] else nil
	end

	-- Total ever earned, or nil (also for currencies without a total).
	function core.getTotal(userId: number, currency: string): number?
		local def = config.Currencies[currency]
		local profile = deps.getProfile(userId)
		if def == nil or def.TotalPath == nil or type(profile) ~= "table" then
			return nil
		end
		local node, key = readPath(profile, def.TotalPath :: { string })
		return if node and isBalance(node[key]) then node[key] else nil
	end

	function core.canAfford(userId: number, currency: string, amount: number): boolean
		local balance = core.get(userId, currency)
		return balance ~= nil and isBalance(amount) and amount <= balance
	end

	-- listener(event) for every change and refusal. Returns a function that unsubscribes.
	function core.subscribe(listener: (event: Event) -> ()): () -> ()
		table.insert(listeners, listener)
		return function()
			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end
	end

	function core.currencies(): { string }
		local ids = {}
		for id in config.Currencies do
			table.insert(ids, id)
		end
		table.sort(ids)
		return ids
	end

	return core
end

return table.freeze(CurrencyCore)

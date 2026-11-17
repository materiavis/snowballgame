--!strict
-- What the zone UI shows (#39, concept 7.6, ADR 0014). Pure: Config.Ui.Text, the formulas and
-- the server-written attributes are passed in, so `lune run tests` checks it.
--
-- Display only. The unlocked zones come from the server's ZonesUnlocked attribute, the coins
-- from Coins, a barrier's zone and whether it can open from the server's BarrierZone and
-- BarrierCanOpen. The price is the same formula the server uses on the same zone. The server
-- decides every unlock and teleport again.

export type Set = { [number]: boolean }

export type WalkInFacts = {
	loaded: boolean, -- DataLoadStatus == "Loaded"
	unlocked: Set?, -- from ZonesUnlocked
	barrierZone: number, -- the zone the barrier ends (BarrierZone)
	canOpen: boolean, -- BarrierCanOpen
	coins: any, -- the Coins attribute
	price: number, -- Formulas.Zones.barrierPrice(barrierZone)
}

export type Row = { zone: number, text: string }

local ZoneView = {}

-- "{zone}"-style placeholders; unknown names stay as written.
function ZoneView.fill(template: string, values: { [string]: any }): string
	return (
		string.gsub(template, "{(%a+)}", function(name: string): string?
			local value = values[name]
			return if value ~= nil then tostring(value) else nil
		end)
	)
end

function ZoneView.toSet(zones: { number }?): Set?
	if zones == nil then
		return nil
	end
	local set: Set = {}
	for _, zone in zones do
		set[zone] = true
	end
	return set
end

-- Whether this player may buy this barrier now, coins aside: loaded, the barrier can open in
-- this Place, its own zone is unlocked and the next one is not. Decides the prompt.
function ZoneView.canBuy(facts: WalkInFacts): boolean
	local unlocked = facts.unlocked
	if not facts.loaded or unlocked == nil or not facts.canOpen then
		return false
	end
	return unlocked[facts.barrierZone] == true and unlocked[facts.barrierZone + 1] ~= true
end

-- Walking into a barrier (or its prompt): the unlock window with enough coins, the missing
-- amount with too few, nothing for a closed, foreign or already open barrier (#39 AC2, AC7).
function ZoneView.walkIn(facts: WalkInFacts): ("Window" | "NeedMore" | "None", number?)
	if not ZoneView.canBuy(facts) then
		return "None", nil
	end
	local coins = facts.coins
	if type(coins) ~= "number" or coins ~= coins or coins < 0 or coins == math.huge then
		return "None", nil
	end
	if coins >= facts.price then
		return "Window", nil
	end
	return "NeedMore", facts.price - coins
end

-- The label above a barrier, or nil once this player has opened it. `priceText` is the price
-- formatted with NumberFormat.price.
function ZoneView.barrierLabel(
	barrierZone: number,
	canOpen: boolean,
	unlocked: Set?,
	text: any,
	priceText: string
): string?
	local nextZone = barrierZone + 1
	if unlocked ~= nil and unlocked[nextZone] then
		return nil
	end
	if not canOpen then
		return ZoneView.fill(text.BarrierClosed, { zone = nextZone })
	end
	return ZoneView.fill(text.BarrierLabel, { zone = nextZone, price = priceText })
end

function ZoneView.question(zone: number, priceText: string, text: any): string
	return ZoneView.fill(text.ZoneUnlockQuestion, { zone = zone, price = priceText })
end

-- Rows of the zone teleport window: one per unlocked zone of this world, ascending (#39 AC4).
-- nil while the profile is not loaded or the attribute is not a valid list.
function ZoneView.teleportRows(
	status: any,
	unlockedValue: any,
	decode: (value: any) -> { number }?,
	worldOf: (zone: number) -> number,
	worldIndex: number,
	names: { string },
	text: any
): { Row }?
	if status ~= "Loaded" then
		return nil
	end
	local zones = decode(unlockedValue)
	if zones == nil then
		return nil
	end
	local rows: { Row } = {}
	for _, zone in zones do
		if worldOf(zone) == worldIndex then
			local name = names[zone] or text.ZoneNamePlaceholder
			table.insert(
				rows,
				{ zone = zone, text = ZoneView.fill(text.ZoneTeleportRow, { zone = zone, name = name }) }
			)
		end
	end
	return rows
end

return table.freeze(ZoneView)

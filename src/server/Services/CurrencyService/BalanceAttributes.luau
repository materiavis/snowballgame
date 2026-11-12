--!strict
-- Balance attributes on the Player (ADR 0007). Pure, so a headless spec can play a live server.
--
-- The balances (`Coins`, `SnowCoins`: every currency id) are the HUD contract (ADR 0008) and
-- are written on every server. The totals (`Total<C>`) are playtest diagnostics, written only
-- when `diagnostics` is on (Studio at PlaceId 0). Clients only read these; a client-side write
-- does not replicate and the server never reads them back.

local BalanceAttributes = {}

export type Options = {
	-- CurrencyCore: currencies(), get(userId, c), getTotal(userId, c).
	core: any,
	-- Anything with SetAttribute (a Player, or a table in specs). nil if gone.
	getPlayer: (userId: number) -> any,
	diagnostics: boolean,
}

export type Mirror = {
	-- Writes every balance (and, with diagnostics, every total) of one player.
	mirror: (player: any, userId: number) -> (),
	-- Listener for CurrencyCore.subscribe. A refusal changes nothing, so it writes nothing.
	onEvent: (event: any) -> (),
}

function BalanceAttributes.new(options: Options): Mirror
	local core = options.core

	local function mirror(player: any, userId: number)
		for _, currency in core.currencies() do
			player:SetAttribute(currency, core.get(userId, currency))
			if options.diagnostics then
				local total = core.getTotal(userId, currency)
				if total ~= nil then
					player:SetAttribute(`Total{currency}`, total)
				end
			end
		end
	end

	local function onEvent(event: any)
		if event.kind == "Refused" then
			return
		end
		local player = options.getPlayer(event.userId)
		if player ~= nil then
			mirror(player, event.userId)
		end
	end

	return table.freeze({ mirror = mirror, onEvent = onEvent })
end

return table.freeze(BalanceAttributes)

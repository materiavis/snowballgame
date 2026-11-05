--!strict
-- Playing together: pet trading and server announcements (concept 7.23, 7.24). Startwerte.
-- Seconds unless noted. The trade history length is Config.Data.TradeHistorySize.

local Social = {
	TradeRequestTimeout = 15, -- the other player sees the request this long
	TradeRequestCooldown = 10, -- at most one request per player in this time (🟦)
	TradeMaxPetsPerSide = 8,
	TradeConfirmCountdown = 5, -- both can still cancel during it
	TradeUnlockZone = 5, -- trading opens from this zone on (🟦)

	AnnouncementInterval = 10, -- at most one server announcement per interval
}

return table.freeze(Social)

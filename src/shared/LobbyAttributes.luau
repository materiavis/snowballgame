--!strict
-- Names of the attributes the Lobby server writes and the Lobby client reads (#37, ADR 0015).
-- One list, so the server and the client cannot drift apart. Pure data.
--
-- Every server: the client needs these to show the countdown, the labels and the arrow.
-- Studio only (PlaceId 0): the diagnostics the playtester reads.

local LobbyAttributes = {
	-- Player, every server.
	PORTAL_STATE = "PortalState", -- Idle | Countdown | Closed | Locked | Busy | Travelling | WaitExit
	PORTAL_MODE = "PortalCurrent", -- the PortalMode the character stands in, "" outside
	PORTAL_COUNTDOWN_ENDS = "PortalCountdownEnds", -- Workspace:GetServerTimeNow() when it ends, 0 otherwise
	SHOW_SINGLE_ARROW = "LobbyShowSingleArrow", -- the first-join arrow to the Singleplayer portal

	-- Player, Studio only.
	PORTAL_LAST = "PortalLast", -- "<mode> <event>", the last portal event
	PORTAL_COUNTDOWN_LEFT = "PortalCountdownLeft", -- seconds left, 0 when not counting
	PORTAL_TRAVEL_RESULT = "PortalTravelResult", -- outcome of the last portal travel
	GROUP_CHEST_LAST = "GroupChestLast", -- the last chest result
	GROUP_MEMBER = "GroupChestMember", -- the last membership answer used
	VIP_ACCESS = "VipAccess", -- the last VIP answer used
	VIP_EJECTIONS = "VipEjections", -- how often the character was moved out of the corner

	-- Workspace, every server (ADR 0009 "StreamingEnabled": positions the client needs while the
	-- part may be streamed out). Set when the station binds.
	SPAWN_POSITION = "LobbySpawnPosition",
	PORTAL_POSITION_PREFIX = "LobbyPortalPosition", -- + PortalMode, e.g. LobbyPortalPositionSingleplayer
	NEWS_NEXT_UPDATE_AT = "LobbyNewsNextUpdateAt", -- Unix seconds, 0 = no date yet
}

return table.freeze(LobbyAttributes)

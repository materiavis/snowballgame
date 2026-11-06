--!strict
-- Lobby, portals and leaderboards (concept 7.1, 7.2). Startwerte. Seconds unless noted.
-- The group chest rewards are in Config/Economy.

local Lobby = {
	PortalCountdown = 3, -- walking out cancels
	PortalPlayerCountRefresh = 30, -- at most this long between player count updates

	-- Leaderboards (7.2): entries, refresh and the automatic Server/Global switch in the Arena.
	LeaderboardEntries = 50, -- Global shows the top 50 (Spielraum)
	LeaderboardRefresh = 300, -- every board refreshes at least every 5 minutes
	ArenaBoardSwitch = 10,
	DefaultBoardFilter = "Global",

	-- Players per server (7.2, decision 15.10.).
	LobbyMaxPlayers = 20,
	SimulatorPlayers = 10,
}

return table.freeze(Lobby)

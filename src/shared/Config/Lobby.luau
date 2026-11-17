--!strict
-- Lobby, portals and leaderboards (concept 7.1, 7.2). Startwerte. Seconds unless noted.
-- The group chest rewards and the group id are in Config/Economy, the VIP pass in
-- Config/Monetization, the map tag names in Config/Map (ADR 0009, ADR 0015).

local Lobby = {
	PortalCountdown = 3, -- walking out cancels
	PortalPlayerCountRefresh = 30, -- at most this long between player count updates

	-- How often the server checks which portal each character stands in (ADR 0015). The
	-- countdown ends at most this much after PortalCountdown. Technical, not a design value.
	PortalCheckInterval = 0.1,
	-- Portal modes that are visible but closed: no countdown, no teleport. Vertical Slice
	-- (owner decision 2026-11-10); #91 removes Multiplayer together with the mode window code.
	ClosedPortalModes = { Multiplayer = true },

	-- Group chest (7.1). Reach is the prompt distance (Config.Ui.Prompts.GroupChest) plus this
	-- slack, because the server sees the character a little later than the client.
	GroupChestReachSlack = 4, -- studs
	-- One open per player at most this often; a double tap is one open (concept 6.5).
	GroupChestCooldown = 1,
	-- A "not a member" answer is asked again after this long, so a player who joins the group
	-- during the session can open the chest without rejoining. A "member" answer is kept.
	GroupMembershipRecheck = 10,

	-- VIP corner (7.1, 9.2): non-VIP characters inside a VipCorner volume are moved out (ADR 0015).
	VipCheckInterval = 0.25,
	VipPushOutMargin = 3, -- studs outside the volume
	-- A "does not own the pass" answer is asked again after this long (a purchase mid-session).
	VipOwnershipRecheck = 30,

	-- News board (7.1): the last update and a countdown to the next. Humans fill these in with
	-- each update. NextUpdateAt is a Unix time in seconds (UTC); 0 means no date yet, and the
	-- board then says the next update is coming soon instead of counting down.
	News = {
		LastUpdate = "Vertical Slice",
		NextUpdateAt = 0,
	},

	-- Leaderboards (7.2): entries, refresh and the automatic Server/Global switch in the Arena.
	LeaderboardEntries = 50, -- Global shows the top 50 (Spielraum)
	LeaderboardRefresh = 300, -- every board refreshes at least every 5 minutes
	ArenaBoardSwitch = 10,
	DefaultBoardFilter = "Global",

	-- Players per server (7.2, decision 15.10.).
	LobbyMaxPlayers = 20,
	SimulatorPlayers = 10,

	-- Look of the portal labels, the countdown and the first-join arrow (Spielraum 7.1: portal
	-- effects, shape of the arrow, size of the boards). Studs unless noted, colours RGB 0-255.
	Display = {
		LabelSize = { 14, 5 }, -- studs, the board above each portal
		LabelMaxDistance = 250,
		LabelOffset = 2, -- studs above PrimaryPart when the portal has no LabelAnchor
		CountdownSize = 120, -- pixels, the ring
		CountdownRingThickness = 8, -- pixels
		CountdownTopFraction = 0.35, -- share of the screen height above the ring centre
		StatusWidth = 320, -- pixels, the "Coming soon" / "still loading" text under the ring
		StatusHeight = 40,
		SingleplayerRGB = { 70, 150, 255 },
		MultiplayerRGB = { 230, 60, 60 },
		ClosedRGB = { 150, 150, 160 },
		ArrowRGB = { 255, 220, 70 },
		ArrowSpacing = 6, -- studs between two chevrons
		ArrowSize = { 3, 0.2, 0.6 }, -- studs: length, thickness, width of one chevron arm
		ArrowHeight = 0.15, -- studs above the spawn's top surface
		ArrowStartGap = 5, -- studs kept free around the spawn point and the portal
		ArrowPulseSeconds = 1.2, -- the chevrons and the portal rim pulse with this period
		NewsTextSize = 48, -- SurfaceGui pixels per stud of the board
	},

	-- Studio-only test layout (LobbyTestGeometry, ADR 0015). Positions are in the spawn's frame:
	-- x right, y up, -z ahead (where the spawn looks). Not design values; the real Plaza is
	-- human-built (world/lobby/Plaza.rbxmx) and needs the same AC1 camera check.
	Test = {
		Origin = { 0, 0, 0 }, -- world position of the spawn's foot
		FloorSize = { 200, 2, 200 },
		SpawnSize = { 6, 1, 6 },
		PortalOffsetX = 14, -- Singleplayer at -x (left), Multiplayer at +x (right)
		PortalDistance = 45,
		PortalSize = { 10, 10, 4 }, -- the walk-in volume
		PortalRingDiameter = 12,
		ChestOffset = { -30, 0, -15 },
		ChestSize = { 5, 4, 4 },
		NewsOffset = { 30, 0, -15 },
		NewsSize = { 10, 6, 1 },
		VipOffset = { 45, 0, -45 },
		VipSize = { 16, 10, 16 },
		-- The fake Simulator server of LobbyStudioSimulatorPlayers.
		SimulatorJobId = "studio-simulator",
	},
}

for _, key in { "ClosedPortalModes", "News", "Display", "Test" } do
	local section = (Lobby :: any)[key]
	for _, value in section do
		if type(value) == "table" then
			table.freeze(value)
		end
	end
	table.freeze(section)
end

return table.freeze(Lobby)

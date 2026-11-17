--!strict
-- What the portal label and the countdown show (concept 7.1; ADR 0015). Pure: texts come from
-- Config.Ui.Text and numbers from NumberFormat.number, both passed in, so a spec checks them.

export type Label = { title: string, status: string?, players: string }

local PortalText = {}

local TITLE_KEYS: { [string]: string } = {
	Singleplayer = "PortalSingleplayer",
	Multiplayer = "PortalMultiplayer",
}

-- Player states (LobbyAttributes.PORTAL_STATE) that show a line of text instead of the ring.
local STATUS_KEYS: { [string]: string } = {
	Closed = "PortalClosed",
	Locked = "PortalLocked",
	Travelling = "PortalTravelling",
}

-- The board above a portal. `count` is the server-written PlayerCount; anything but a whole
-- number >= 0 shows as 0, since the client never trusts its own guess.
function PortalText.label(
	mode: string,
	count: any,
	closed: boolean,
	text: { [string]: string },
	formatNumber: (number) -> string
): Label
	local players = if type(count) == "number" and count == count and count >= 0 and count % 1 == 0 then count else 0
	local key = TITLE_KEYS[mode]
	return {
		title = if key then text[key] else mode,
		status = if closed then text.PortalClosed else nil,
		players = (string.gsub(text.PortalPlayers, "{count}", formatNumber(players))),
	}
end

-- The whole seconds the countdown shows: 3, 2, 1 for a 3 s countdown, never below 1 while it
-- runs and 0 when it is over.
function PortalText.secondsShown(endsAt: number, now: number): number
	local left = endsAt - now
	if left <= 0 then
		return 0
	end
	return math.max(1, math.ceil(left - 1e-6))
end

-- The status line for a player state, or nil when the state shows nothing (Idle, WaitExit,
-- Busy) or the ring (Countdown).
function PortalText.status(state: any, text: { [string]: string }): string?
	local key = if type(state) == "string" then STATUS_KEYS[state] else nil
	return if key then text[key] else nil
end

return table.freeze(PortalText)

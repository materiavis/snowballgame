--!strict
-- The news board text (concept 7.1: latest update and a countdown to the next; ADR 0015).
-- Pure: texts from Config.Ui.Text, the title from Config.Lobby.News, times passed in.

export type Lines = { title: string, last: string, next: string }

local NewsText = {}

-- "2d 04:05:06", or "04:05:06" under a day. Whole seconds, rounded up so it reads 00:00:01 in
-- the last second and never shows 00:00:00 before the time is reached.
function NewsText.countdown(seconds: number): string
	local left = math.max(0, math.ceil(seconds - 1e-6))
	local days = left // 86400
	local hours = (left % 86400) // 3600
	local minutes = (left % 3600) // 60
	local secs = left % 60
	local clock = string.format("%02d:%02d:%02d", hours, minutes, secs)
	return if days > 0 then `{days}d {clock}` else clock
end

-- `nextAt` is the Unix time of the next update (0 or past: "coming soon").
function NewsText.lines(text: { [string]: string }, lastUpdate: string, nextAt: any, now: number): Lines
	local nextLine
	if type(nextAt) == "number" and nextAt == nextAt and nextAt > now then
		nextLine = (string.gsub(text.NewsNextUpdate, "{time}", NewsText.countdown(nextAt - now)))
	else
		nextLine = text.NewsNextUpdateSoon
	end
	return {
		title = text.NewsTitle,
		last = (string.gsub(text.NewsLastUpdate, "{title}", function()
			return lastUpdate
		end)),
		next = nextLine,
	}
end

return table.freeze(NewsText)

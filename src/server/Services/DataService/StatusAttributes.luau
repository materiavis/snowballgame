--!strict
-- Player attributes for the profile state (ADR 0006). Pure, so a headless spec can play a live
-- server: players come from `getPlayer`, events from DataCore.subscribe.
--
-- DataLoadStatus is the HUD contract (ADR 0008) and is written on every server, Studio or not;
-- without it a live HUD would show "–" forever. The other attributes are playtest diagnostics
-- and are written only when `diagnostics` is on (Studio).

local StatusAttributes = {}

StatusAttributes.LIVE = table.freeze({ "DataLoadStatus" })
StatusAttributes.DIAGNOSTIC =
	table.freeze({ "DataLoadDetail", "DataPortalLocked", "DataSaveSeq", "DataLastSave", "DataSaveFailures" })

-- Mirrors DataCore.Event (the Roblox layer requires through WaitForChild and cannot see it).
export type Event = {
	kind: "Status" | "Save",
	userId: number,
	status: string?,
	detail: string?,
	ok: boolean?,
	reason: string?,
	seq: number?,
}

export type Options = {
	-- Anything with SetAttribute/GetAttribute (a Player, or a table in specs). nil if gone.
	getPlayer: (userId: number) -> any,
	getSaveSeq: (userId: number) -> number?,
	diagnostics: boolean,
}

-- Returns a listener for DataCore.subscribe.
function StatusAttributes.listener(options: Options): (event: Event) -> ()
	local diagnostics = options.diagnostics

	return function(event: Event)
		local player = options.getPlayer(event.userId)
		if player == nil then
			return
		end
		if event.kind == "Status" then
			player:SetAttribute("DataLoadStatus", event.status)
			if diagnostics then
				player:SetAttribute("DataLoadDetail", event.detail or "")
				player:SetAttribute("DataPortalLocked", event.status ~= "Loaded")
				player:SetAttribute("DataSaveSeq", options.getSaveSeq(event.userId))
			end
		elseif diagnostics then
			local outcome = if event.ok then `ok seq={event.seq}` else `failed: {event.detail}`
			player:SetAttribute("DataLastSave", `{event.reason} {outcome}`)
			if event.ok then
				player:SetAttribute("DataSaveSeq", event.seq)
			else
				player:SetAttribute("DataSaveFailures", ((player:GetAttribute("DataSaveFailures") :: number?) or 0) + 1)
			end
		end
	end
end

return table.freeze(StatusAttributes)

--!strict
-- Names of the attributes TutorialService writes and the tutorial controllers read (#42,
-- ADR 0017), and the list format they use. Pure, no requires.
--
-- Every server (the client needs them to draw the hints):
--   Player  TutorialActive  string   hint ids showing now, in Config.Tutorial.Order, comma-joined;
--                                    "" while the profile is not loaded
--   Player  TutorialDone    string   hint ids done, same format; "" while not loaded
--   Player  TutorialTarget  Vector3  where the World-channel hint points (absent when none)
-- Studio only (PlaceId 0): the diagnostics the playtester reads.

local TutorialAttributes = {
	ACTIVE = "TutorialActive",
	DONE = "TutorialDone",
	TARGET = "TutorialTarget",

	-- Studio only.
	LAST = "TutorialLast", -- "<id> <event> source=<source>", the last change
	LAST_AT = "TutorialLastAt", -- Workspace:GetServerTimeNow() of the last change
	RETURN_VISIT = "TutorialReturnVisit", -- Lobby: this load is a later visit (Multiplayer arrow)
	WALKED = "TutorialWalked", -- studs walked while the controls hint shows
	REFUSALS = "TutorialRefusals", -- refused TutorialHintDone reports
}

-- "A,B" from { "A", "B" }; "" for none.
function TutorialAttributes.encode(ids: { string }): string
	return table.concat(ids, ",")
end

-- The ids of an encoded list. Anything that is not a string reads as an empty list.
function TutorialAttributes.decode(value: any): { string }
	local out: { string } = {}
	if type(value) ~= "string" or value == "" then
		return out
	end
	for _, id in string.split(value, ",") do
		if id ~= "" then
			table.insert(out, id)
		end
	end
	return out
end

-- True when `id` is in the encoded list.
function TutorialAttributes.has(value: any, id: string): boolean
	for _, entry in TutorialAttributes.decode(value) do
		if entry == id then
			return true
		end
	end
	return false
end

return table.freeze(TutorialAttributes)

--!strict
-- The first-join arrow rule (concept 7.1, 10.1; ADR 0015) on the schema v1 flag
-- `tutorial.seenSingleArrow`. Pure, works on the live profile table.
--
-- The flag is set when the first portal travel starts, before TravelService saves: a real
-- teleport releases the session in that save, so a flag set afterwards could never be stored.
-- If the travel does not happen (refused, save failed, teleport failed), the flag goes back to
-- its old value and the arrow shows again. #42 (onboarding) adds the Multiplayer arrow on the
-- same pattern with `tutorial.seenMultiArrow`.

local FirstJoinArrow = {}

-- Outcomes of TravelService.Travel after which the player is still here and did not travel.
local NOT_TRAVELLED = table.freeze({
	Refused = true,
	SaveFailed = true,
	TeleportFailed = true,
	NotLoaded = true,
})

local function tutorialOf(profile: any): any
	if type(profile) ~= "table" or type(profile.tutorial) ~= "table" then
		return nil
	end
	return profile.tutorial
end

-- Show the arrow only for a loaded profile that has not seen it. Without a profile (loading or
-- failed) nothing is shown, so a returning player whose load failed never sees it by mistake.
function FirstJoinArrow.shouldShow(profile: any): boolean
	local tutorial = tutorialOf(profile)
	return tutorial ~= nil and tutorial.seenSingleArrow ~= true
end

-- Sets the flag. Returns true when it changed (this is the first travel), so the caller knows
-- whether there is anything to undo.
function FirstJoinArrow.markSeen(profile: any): boolean
	local tutorial = tutorialOf(profile)
	if tutorial == nil or tutorial.seenSingleArrow == true then
		return false
	end
	tutorial.seenSingleArrow = true
	return true
end

-- After the travel: undo the flag when markSeen changed it and the player did not travel.
-- Returns true when it was undone.
function FirstJoinArrow.afterTravel(profile: any, changed: boolean, outcome: string): boolean
	if not changed or not NOT_TRAVELLED[outcome] then
		return false
	end
	local tutorial = tutorialOf(profile)
	if tutorial == nil then
		return false
	end
	tutorial.seenSingleArrow = false
	return true
end

-- Studio reset (LobbyStudioReset): the arrow shows again.
function FirstJoinArrow.reset(profile: any): boolean
	local tutorial = tutorialOf(profile)
	if tutorial == nil then
		return false
	end
	tutorial.seenSingleArrow = false
	return true
end

return table.freeze(FirstJoinArrow)

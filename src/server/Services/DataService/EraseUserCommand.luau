--!strict
-- OWNER-RUN ADMIN SCRIPT for Roblox right-to-erasure requests (concept 12.1, ADR 0006).
-- Never exposed through a remote and never called by game code. An owner runs it from the
-- Studio command bar of the published Place (Game Settings > Security > "Enable Studio
-- Access to API Services" on), after the player has left every server:
--
--   require(game.ServerScriptService.Server.Services.DataService.EraseUserCommand)(123456789, "ERASE 123456789")
--
-- The second argument must repeat the user id, so a mistyped id cannot erase the wrong player.
-- At PlaceId 0 (build/test.rbxl) it only erases the in-memory fake store of that session.

local DataService = require(script.Parent)

return function(userId: number, confirmation: string): boolean
	if type(userId) ~= "number" or userId < 1 or userId % 1 ~= 0 then
		warn("[EraseUser] userId must be a positive whole number")
		return false
	end
	if confirmation ~= `ERASE {userId}` then
		warn(`[EraseUser] refused: the second argument must be exactly "ERASE {userId}"`)
		return false
	end
	local ok, err = DataService.EraseUser(userId)
	if ok then
		print(`[EraseUser] erased profile and leaderboard entries of {userId} (store={DataService.GetStoreMode()})`)
	else
		warn(`[EraseUser] erasing {userId} failed: {err}`)
	end
	return ok
end

--!strict
-- Server path for the centre pop-ups (concept 10.2, #90, ADR 0008). Server features (selling
-- #38, eggs #41) call PopupService.show(player, key, numbers) to show a short text to one player.
-- Fires the declared Popup remote (Net, ADR 0005) with a text key from Config.Ui.PopupTexts and
-- up to Config.Net.Popup.MaxNumbers numbers; the client formats the text. No free text is sent.
-- The client never sends this remote: there is no server handler, so a client call is dropped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetConfig = require(Shared:WaitForChild("Config"):WaitForChild("Net")) :: any
local UiConfig = require(Shared:WaitForChild("Config"):WaitForChild("Ui")) :: any
local PopupText = require(Shared:WaitForChild("PopupText"))
local NetService = require(script.Parent:WaitForChild("NetService"))

local REMOTE = "Popup"

local PopupService = {}

local function remote(): RemoteEvent
	return NetService.getRemote(REMOTE) :: RemoteEvent
end

-- Returns false (and warns) for an invalid key or numbers, or a player who has left. A bad
-- call is a bug in the calling feature, so it is never sent.
function PopupService.show(player: Player, key: string, numbers: { number }?): boolean
	local list = numbers or {}
	local ok, reason = PopupText.check(key, list, UiConfig, NetConfig.Popup)
	if not ok then
		warn(`[PopupService] not sent: {reason}`)
		return false
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	remote():FireClient(player, key, table.unpack(list))
	return true
end

-- Same pop-up for every player on this server.
function PopupService.showAll(key: string, numbers: { number }?): boolean
	local list = numbers or {}
	local ok, reason = PopupText.check(key, list, UiConfig, NetConfig.Popup)
	if not ok then
		warn(`[PopupService] not sent: {reason}`)
		return false
	end
	remote():FireAllClients(key, table.unpack(list))
	return true
end

function PopupService.Start()
	-- Creates the remotes now, so clients that wait for Popup find it even before a feature
	-- shows the first pop-up.
	NetService.Start()
end

return PopupService

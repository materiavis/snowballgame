--!strict
-- Studio-only placeholder entries for the hidden left-edge buttons (#90, ADR 0008 "Studio
-- switches"). The server's HudTestButtons switch mirrors to the player attribute of the same
-- name; while it is true, this registers inert Pets, ZoneTeleport and Lobby entries, so the
-- hidden -> visible path, the 44 px floor and the layout can be checked without the features.
-- Each placeholder only prints and shows the "Coming soon" pop-up. Does nothing outside Studio
-- at PlaceId 0.

local RunService = game:GetService("RunService")

local Controllers = script.Parent.Parent.Parent:WaitForChild("Controllers")
local MenuController = require(Controllers:WaitForChild("MenuController"))
local PopupController = require(Controllers:WaitForChild("PopupController"))

local ATTRIBUTE = "HudTestButtons"
local PLACEHOLDERS = { "Pets", "ZoneTeleport", "Lobby" }
local POPUP_TEXT = "PlaceholderButton"

local TestButtons = {}

function TestButtons.start(player: Player)
	if not (RunService:IsStudio() and game.PlaceId == 0) then
		return
	end
	local unregister: { () -> () } = {}

	local function apply()
		local wanted = player:GetAttribute(ATTRIBUTE) == true
		if wanted and #unregister == 0 then
			for _, id in PLACEHOLDERS do
				-- A feature that already registered its real button keeps it.
				if table.find(MenuController.visibleButtons(), id) then
					continue
				end
				table.insert(
					unregister,
					MenuController.registerButton({
						id = id,
						activate = function()
							print(`[HudTest] placeholder button {id} activated`)
							PopupController.show(POPUP_TEXT)
						end,
					})
				)
			end
			print(`[HudTest] placeholder buttons registered: {table.concat(PLACEHOLDERS, ", ")}`)
		elseif not wanted and #unregister > 0 then
			for _, done in unregister do
				done()
			end
			table.clear(unregister)
			print("[HudTest] placeholder buttons unregistered")
		end
	end

	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(apply)
	apply()
end

return table.freeze(TestButtons)

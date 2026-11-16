--!strict
-- Studio-only playtest support for SellService (ADR 0012 "Studio playtest support"). SellService
-- binds it only in Studio at game.PlaceId == 0. Switches on `host` (ServerScriptService):
--   SellTargetUserId      number, the player the switches act on; 0 = every player
--   SellScaleTestGeometry number: n builds the test scale in Workspace.Map.SellScaleTest with
--                         ZoneIndex n in front of the target; 0 removes it
--   SellAddFindValue      number, idle 0: adds that finds value to the target's ball through
--                         the same API finds (#40) use, then resets to 0
--   SellFactorOverride    string: "pet=<n> rebirths=<n> bonus=<Flag>,<Flag>" replaces those
--                         factors in every sale until set to ""
-- Diagnostics: the Config.Sell.DiagnosticAttributes on the Player after every sale and refusal.

local Players = game:GetService("Players")

local SaleOverride = require(script.Parent:WaitForChild("SaleOverride"))

export type Hooks = {
	-- Builds (zone > 0) or removes (0) the test scale in front of `origin`; returns a log line.
	setTestGeometry: (zone: number, origin: CFrame?) -> string,
	addFindValue: (player: Player, value: any) -> (boolean, string?),
	findsValue: (player: Player) -> number,
	-- Parses and applies the override text; returns a log line.
	setOverride: (text: any) -> string,
}

local TARGET_SWITCH = "SellTargetUserId"
local TEST_GEOMETRY_SWITCH = "SellScaleTestGeometry"
local ADD_FIND_SWITCH = "SellAddFindValue"
local OVERRIDE_SWITCH = "SellFactorOverride"

local SellSwitches = {}

SellSwitches.Names = table.freeze({
	Target = TARGET_SWITCH,
	TestGeometry = TEST_GEOMETRY_SWITCH,
	AddFindValue = ADD_FIND_SWITCH,
	FactorOverride = OVERRIDE_SWITCH,
})

local function default(host: Instance, name: string, value: any)
	if host:GetAttribute(name) == nil then
		host:SetAttribute(name, value)
	end
end

function SellSwitches.bind(host: Instance, hooks: Hooks)
	default(host, TARGET_SWITCH, 0)
	default(host, TEST_GEOMETRY_SWITCH, 0)
	default(host, ADD_FIND_SWITCH, 0)
	default(host, OVERRIDE_SWITCH, "")

	local function targets(): { Player }
		local target = host:GetAttribute(TARGET_SWITCH)
		if type(target) == "number" and target ~= 0 then
			local player = Players:GetPlayerByUserId(target)
			if player == nil then
				warn(`[SellService] {TARGET_SWITCH}: no player with UserId {target}`)
				return {}
			end
			return { player }
		end
		return Players:GetPlayers()
	end

	host:GetAttributeChangedSignal(TEST_GEOMETRY_SWITCH):Connect(function()
		local zone = host:GetAttribute(TEST_GEOMETRY_SWITCH)
		if type(zone) ~= "number" or zone % 1 ~= 0 or zone < 0 then
			warn(`[SellService] {TEST_GEOMETRY_SWITCH}: expected 0 or a zone number, got {tostring(zone)}`)
			return
		end
		local origin: CFrame? = nil
		local target = targets()[1]
		local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			origin = root.CFrame
		end
		print(`[SellService] {TEST_GEOMETRY_SWITCH} {zone} -> {hooks.setTestGeometry(zone, origin)}`)
	end)

	host:GetAttributeChangedSignal(ADD_FIND_SWITCH):Connect(function()
		local value = host:GetAttribute(ADD_FIND_SWITCH)
		if value == 0 or value == nil then
			return
		end
		host:SetAttribute(ADD_FIND_SWITCH, 0)
		for _, player in targets() do
			local ok, refusal = hooks.addFindValue(player, value)
			local result = if ok then `finds in ball now {hooks.findsValue(player)}` else `refused: {refusal}`
			print(`[SellService] {ADD_FIND_SWITCH} {player.Name} ({player.UserId}) +{tostring(value)} {result}`)
		end
	end)

	host:GetAttributeChangedSignal(OVERRIDE_SWITCH):Connect(function()
		print(`[SellService] {OVERRIDE_SWITCH} -> {hooks.setOverride(host:GetAttribute(OVERRIDE_SWITCH))}`)
	end)
end

-- Number attributes for a reader that recomputes the formula; text for a quick look.
function SellSwitches.writeDiagnostics(player: Player, names: any, event: any, describe: (event: any) -> string)
	local sale = event.sale
	if event.kind == "Sale" then
		player:SetAttribute(names.Sales, ((player:GetAttribute(names.Sales) :: number?) or 0) + 1)
		player:SetAttribute(names.LastRefusal, "")
	else
		player:SetAttribute(names.Refusals, ((player:GetAttribute(names.Refusals) :: number?) or 0) + 1)
		player:SetAttribute(names.LastRefusal, event.refusal)
	end
	player:SetAttribute(names.LastSale, describe(event))
	if sale == nil then
		return
	end
	player:SetAttribute(names.LastCoins, if event.kind == "Sale" then sale.coins else 0)
	player:SetAttribute(names.LastSizeMetres, sale.sizeMetres)
	player:SetAttribute(names.LastBallValue, sale.ballValue)
	player:SetAttribute(names.LastFindsValue, sale.findsValue)
	player:SetAttribute(names.LastPetMultiplier, sale.petMultiplier)
	player:SetAttribute(names.LastRebirths, sale.rebirths)
	player:SetAttribute(names.LastRebirthMultiplier, sale.rebirthMultiplier)
	player:SetAttribute(names.LastSellValueLevel, sale.sellValueLevel)
	player:SetAttribute(names.LastSellMultiplier, sale.sellMultiplier)
	player:SetAttribute(names.LastBonus, sale.bonus)
	player:SetAttribute(names.LastBonusFlags, SaleOverride.describeFlags(sale.flags))
	player:SetAttribute(names.LastZone, sale.zone)
	player:SetAttribute(names.LastBalance, sale.balance)
end

return table.freeze(SellSwitches)

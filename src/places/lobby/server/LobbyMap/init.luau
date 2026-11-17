--!strict
-- Binds the Lobby map entries of ADR 0009 "Lobby (7.1)" for the Lobby services (#37, ADR 0015).
-- Not a service (no Start): the loader requires it but does not count it.
--
-- bindTag(tag, check, onBind, onUnbind) calls onBind for every tagged instance below
-- Workspace.Map that the check accepts, now and whenever one is added, and onUnbind when it
-- goes. An invalid instance warns once (`[MapContract] …, ignored`) and is not bound. Nothing
-- throws, so one bad part never stops the Lobby.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Map")) :: any
local AnswerCache = require(script:WaitForChild("AnswerCache"))
local Box = require(script:WaitForChild("Box"))
local MapRules = require(script:WaitForChild("MapRules"))

export type Verdict = MapRules.Verdict

local LobbyMap = {}

LobbyMap.Config = MapConfig
LobbyMap.Box = Box
LobbyMap.AnswerCache = AnswerCache

local function mapFolder(): Instance?
	return Workspace:FindFirstChild(MapConfig.FolderName)
end

LobbyMap.rules = MapRules.new({
	stationStreamingMode = MapConfig.StationStreamingMode,
	portalModeAttribute = MapConfig.PortalModeAttribute,
	portalModes = MapConfig.PortalModes,
}, {
	inMap = function(node: any): boolean
		local folder = mapFolder()
		return folder ~= nil and node:IsDescendantOf(folder)
	end,
	isA = function(node: any, className: string): boolean
		return node:IsA(className)
	end,
	primaryPart = function(node: any): any
		return node.PrimaryPart
	end,
	streamingMode = function(node: any): string
		return node.ModelStreamingMode.Name
	end,
	attribute = function(node: any, name: string): any
		return node:GetAttribute(name)
	end,
})

local warned: { [string]: { [Instance]: boolean } } = {}

-- Returns a function listing the bound instances, sorted by full name so "the first portal of a
-- mode" is the same on every start.
function LobbyMap.bindTag(
	tag: string,
	check: (instance: Instance) -> Verdict,
	onBind: (instance: Instance, verdict: Verdict) -> (),
	onUnbind: ((instance: Instance) -> ())?
): () -> { Instance }
	local bound: { [Instance]: boolean } = {}
	warned[tag] = warned[tag] or setmetatable({}, { __mode = "k" }) :: any

	local function bind(instance: Instance)
		if bound[instance] then
			return
		end
		local verdict = check(instance)
		if verdict.status == "OutOfScope" then
			return
		end
		if verdict.status == "Invalid" then
			if not warned[tag][instance] then
				warned[tag][instance] = true
				warn(MapRules.warning(tag, instance:GetFullName(), verdict.problem or "invalid"))
			end
			return
		end
		bound[instance] = true
		onBind(instance, verdict)
	end

	local function unbind(instance: Instance)
		if not bound[instance] then
			return
		end
		bound[instance] = nil
		if onUnbind then
			onUnbind(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unbind)
	for _, instance in CollectionService:GetTagged(tag) do
		bind(instance)
	end

	return function(): { Instance }
		local list = {}
		for instance in bound do
			if instance.Parent ~= nil then
				table.insert(list, instance)
			end
		end
		table.sort(list, function(a, b)
			return a:GetFullName() < b:GetFullName()
		end)
		return list
	end
end

-- Warns once at start when a tag has no entry (or more than one where exactly one is expected).
function LobbyMap.warnCount(tag: string, count: number, expected: "one" | "some")
	local message = MapRules.countWarning(tag, count, expected)
	if message then
		warn(message)
	end
end

-- True when `position` is inside the box of `part`.
function LobbyMap.contains(part: BasePart, position: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(position)
	return Box.contains(localPoint.X, localPoint.Y, localPoint.Z, { part.Size.X, part.Size.Y, part.Size.Z })
end

-- The HumanoidRootPart of a living character, or nil.
function LobbyMap.rootOf(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

return table.freeze(LobbyMap)

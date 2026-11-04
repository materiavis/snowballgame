--!strict
-- Creates every remote declared in Shared.Net under ReplicatedStorage.Remotes and puts the
-- Net guard (rate, argument count, types and ranges, authorize) in front of each one.
-- Other services register handlers with NetService.handle and never touch a remote's
-- OnServerEvent / OnServerInvoke themselves.
--
-- Setup runs on the first Start() or handle() call, whichever comes first. The loader starts
-- services in no fixed order, so this is how Net "initialises first" without the loader
-- having to know about it.
--
-- In Studio each remote also carries counter attributes (NetAccepted, NetRejected,
-- NetRejected<Reason>, NetHandlerErrors, NetLastRejection) so a playtest can read them.
-- Live servers skip that: clients do not need to see why their calls are dropped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NetModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
local Net = require(NetModule)
local Guard = require(NetModule:WaitForChild("Guard"))
local RateLimiter = require(NetModule:WaitForChild("RateLimiter"))
local Stats = require(NetModule:WaitForChild("Stats"))

-- Mirrors Net/Guard and Net/Stats. The requires above go through WaitForChild, so their
-- exported types are not visible here.
type Handler = (player: Player, ...any) -> ...any
type Counts = { accepted: number, rejected: number, handlerErrors: number, byReason: { [string]: number } }
type Listener = (event: { remote: string, outcome: string, reason: string?, detail: string?, player: any }) -> ()

local NetService = {}

local stats = Stats.new()
local handlers: { [string]: Handler } = {}
local remotes: { [string]: Instance } = {}
local started = false

local function publishToAttributes()
	stats:subscribe(function(event)
		local remote = remotes[event.remote]
		if remote == nil then
			return
		end
		local counts = stats:get(event.remote)
		remote:SetAttribute("NetAccepted", counts.accepted)
		remote:SetAttribute("NetRejected", counts.rejected)
		remote:SetAttribute("NetHandlerErrors", counts.handlerErrors)
		if event.reason then
			remote:SetAttribute(`NetRejected{event.reason}`, counts.byReason[event.reason])
			remote:SetAttribute("NetLastRejection", `{event.reason}: {event.detail or ""}`)
		end
	end)
end

local function setUp()
	if started then
		return
	end
	started = true

	-- A Remotes folder from elsewhere (a Rojo mapping, a plugin) would hold unguarded remotes.
	if ReplicatedStorage:FindFirstChild(Net.FOLDER_NAME) then
		error(`NetService: ReplicatedStorage.{Net.FOLDER_NAME} already exists; only NetService creates it`, 0)
	end

	local isStudio = RunService:IsStudio()
	if isStudio then
		publishToAttributes()
	end

	local folder = Instance.new("Folder")
	folder.Name = Net.FOLDER_NAME

	local limiters = {}
	local count = 0
	for name, definition in Net.Definitions do
		local limiter = RateLimiter.new(definition.rateLimit, os.clock)
		table.insert(limiters, limiter)

		local guarded = Guard.new(definition, {
			limiter = limiter,
			stats = stats,
			getHandler = function()
				return handlers[name]
			end,
			reportError = function(remoteName, message)
				warn(`[NetService] handler for {remoteName} errored: {message}`)
			end,
		})

		local remote: Instance
		if definition.kind == "Event" then
			local event = Instance.new("RemoteEvent")
			event.OnServerEvent:Connect(guarded)
			remote = event
		else
			local func = Instance.new("RemoteFunction")
			func.OnServerInvoke = guarded
			remote = func
		end
		remote.Name = name
		if isStudio then
			remote:SetAttribute("NetAccepted", 0)
			remote:SetAttribute("NetRejected", 0)
		end
		remote.Parent = folder
		remotes[name] = remote
		count += 1
	end

	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:forget(player)
		end
	end)

	-- Parented last, so a client that finds the folder also finds every remote in it.
	folder.Parent = ReplicatedStorage
	print(`[NetService] created {count} remotes in ReplicatedStorage.{Net.FOLDER_NAME}`)
end

-- Registers the server handler for a declared remote. It only runs for calls that passed
-- every check, and receives (player, ...validated args). Errors on an undeclared or
-- already handled remote, so wiring mistakes show up at startup.
function NetService.handle(name: string, handler: Handler)
	setUp()
	if not Net.isDeclared(name) then
		error(`NetService.handle: remote '{name}' is not declared in Net/Remotes`, 2)
	end
	if handlers[name] ~= nil then
		error(`NetService.handle: remote '{name}' already has a handler`, 2)
	end
	handlers[name] = handler
end

-- Hook for the analytics service (#43): receives every accepted, rejected and errored call.
function NetService.subscribe(listener: Listener)
	stats:subscribe(listener)
end

function NetService.getRemote(name: string): Instance
	setUp()
	local remote = remotes[name]
	if remote == nil then
		error(`NetService.getRemote: remote '{name}' is not declared in Net/Remotes`, 2)
	end
	return remote
end

function NetService.getCounts(name: string): Counts
	return stats:get(name)
end

function NetService.getTotalRejected(): number
	return stats:totalRejected()
end

function NetService.Start()
	setUp()
end

return NetService

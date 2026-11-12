--!strict
-- Which server of the destination Place a travel goes to (concept 5.6, 6.5, ADR 0010).
-- Pure, no requires: presence, friend lookup, ReserveServer and the private context are injected.
--
--   Lobby                -> public (Roblox matchmaking).
--   Arena                -> the reserved match server the caller passed, else a new reserved one.
--   Simulator, private   -> the reserved Simulator server of this private context (mapping in
--                           PresenceStore), else a new reserved one that is then mapped.
--   Simulator, public    -> a friend's server of that world with a free place (preference 5.6),
--                           else public: Roblox matchmaking picks a server with a free place and
--                           opens a new one when all are full (6.5 "Simulator-Server ist voll").

export type Target = {
	server: "Public" | "Friend" | "Reserved",
	jobId: string?, -- Friend
	friendId: number?, -- Friend
	accessCode: string?, -- Reserved
	reservedNew: boolean?, -- Reserved: opened for this travel
	privateKey: string?, -- Reserved in a private context
}

export type Deps = {
	presence: {
		findFriendServer: (
			friendIds: { number },
			world: number,
			maxPlayers: number,
			excludeJobId: string?
		) -> (string?, number?),
		getReserved: (key: string, world: number) -> { accessCode: string, privateServerId: string }?,
		setReserved: (key: string, world: number, accessCode: string, privateServerId: string) -> boolean,
	},
	friendsOf: (userId: number) -> { number },
	-- ReserveServer: true, accessCode, privateServerId; or false, error.
	reserve: (placeId: number) -> (boolean, string?, string?),
	privateKey: () -> string?,
	maxSimulatorPlayers: number,
	ownJobId: string,
	log: (level: "info" | "warn", message: string) -> (),
}

export type Options = { accessCode: string? }

local ServerChoice = {}

function ServerChoice.public(): Target
	return { server = "Public" }
end

function ServerChoice.describe(target: Target): string
	if target.server == "Friend" then
		return `Friend(jobId={target.jobId}, friend={target.friendId})`
	elseif target.server == "Reserved" then
		local which = if target.reservedNew then "new" else "existing"
		local private = if target.privateKey then `, private={target.privateKey}` else ""
		return `Reserved({which}, code={target.accessCode}{private})`
	end
	return "Public"
end

function ServerChoice.new(deps: Deps)
	local chooser = {}

	local function reserveNew(placeId: number): (Target?, string?, string?)
		local ok, accessCode, privateServerId = deps.reserve(placeId)
		if not ok or type(accessCode) ~= "string" or accessCode == "" then
			deps.log("warn", `ReserveServer for PlaceId {placeId} failed: {tostring(accessCode)}`)
			return nil, "ReserveFailed", nil
		end
		return { server = "Reserved", accessCode = accessCode, reservedNew = true }, nil, privateServerId
	end

	-- dest is a Destinations.Destination. Yields (presence reads, friend list, ReserveServer).
	function chooser.choose(userId: number, dest: any, options: Options?): (Target?, string?)
		if dest.role == "Lobby" then
			return ServerChoice.public(), nil
		end

		if dest.role == "Arena" then
			local code = if options then options.accessCode else nil
			if type(code) == "string" and code ~= "" then
				return { server = "Reserved", accessCode = code, reservedNew = false }, nil
			end
			local target, why = reserveNew(dest.placeId)
			return target, why
		end

		local world = dest.world :: number
		local key = deps.privateKey()
		if key then
			local existing = deps.presence.getReserved(key, world)
			if existing then
				return {
					server = "Reserved",
					accessCode = existing.accessCode,
					reservedNew = false,
					privateKey = key,
				},
					nil
			end
			local target, why, privateServerId = reserveNew(dest.placeId)
			if target == nil then
				return nil, why
			end
			target.privateKey = key
			if type(privateServerId) ~= "string" or privateServerId == "" then
				deps.log("warn", `ReserveServer gave no PrivateServerId; private mapping for {key} not stored`)
			elseif not deps.presence.setReserved(key, world, target.accessCode :: string, privateServerId) then
				-- Best effort: the next travel opens another reserved server instead of this one.
				deps.log("warn", `private mapping for {key} world {world} not stored`)
			end
			return target, nil
		end

		local okFriends, friends = pcall(deps.friendsOf, userId)
		if okFriends and type(friends) == "table" and #friends > 0 then
			local jobId, friendId =
				deps.presence.findFriendServer(friends, world, deps.maxSimulatorPlayers, deps.ownJobId)
			if jobId then
				return { server = "Friend", jobId = jobId, friendId = friendId }, nil
			end
		elseif not okFriends then
			deps.log("warn", `friend lookup for {userId} failed: {tostring(friends)}; no friend preference`)
		end
		return ServerChoice.public(), nil
	end

	return table.freeze(chooser)
end

return table.freeze(ServerChoice)

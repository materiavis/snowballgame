--!strict
-- Finds (concept 7.7, 8.5, 6.5, ADR 0016). Pure: the odds, the find value formula, the profile,
-- the unlocked zones, the finds value of the ball, the generator and the clocks are injected,
-- so headless specs run it against the real Config, Rng and DataService fake store.
--
-- * Points: every bound FindPoint anchor is a slot with its zone and position. Finds lie only
--   there (AC1).
-- * Per player (7.7 🟦): each point holds at most one find of that player. A point that has
--   been empty for Config.Finds.SpawnInterval seconds gets a new find, rolled on the server with
--   the zone's table (zones 1-5 of a world have no Legendary, AC3) and the secret find.
-- * Pickup: the server's view of the player's ball within the Magnet radius of a find (gap
--   between the ball's surface and the point), the owner at the ball and the find's zone
--   unlocked. Then, without a yield: the value (share of a full ball of that zone, AC2) goes into
--   the ball, the find goes into sim.collection.finds the first time (AC5: it is in the profile
--   from the pickup on), the secret find adds its title, and the find sticks in the ball until
--   the sale (AC4).
-- No value comes from a client.

export type Point = {
	slot: number,
	key: any,
	zone: number,
	x: number,
	y: number,
	z: number,
	name: string,
}

export type Spawned = {
	slot: number,
	findId: string,
	rarity: string,
	zone: number,
	roll: number?, -- nil for a forced rarity
	forced: string?, -- "Rarity" or "Roll" (Studio switches)
	at: number,
}

-- Studio switches FindForceRarity / FindForceRoll for one player.
export type Force = { rarity: string?, roll: number? }

-- The server's view of a ball: centre and radius in studs.
export type Ball = { x: number, y: number, z: number, radius: number }

export type Event = {
	kind: "Spawn" | "Remove" | "Collect" | "ClearBall" | "Reset" | "Refused",
	userId: number,
	slot: number?,
	findId: string?,
	rarity: string?,
	zone: number?,
	point: Point?,
	roll: number?,
	forced: string?,
	forceRefused: string?, -- a forced rarity this zone's table does not have
	value: number?,
	valueRefusal: string?,
	first: boolean?, -- first time in the collection
	title: string?, -- title the secret find gave
	newTitle: boolean?,
	collectionProblem: string?,
	refusal: string?,
	reason: string?,
}

export type Deps = {
	config: any, -- Config.Finds
	findOdds: (zone: number) -> { { id: string, weight: number } }, -- Rng.findOdds
	pick: (entries: { { id: string, weight: number } }, roll: number) -> string, -- Rng.pick
	findValue: (zone: number, rarity: string) -> number, -- Formulas.Economy.findValue
	worldOf: (zone: number) -> number,
	generator: { next: () -> number },
	now: () -> number, -- seconds, monotonic (spawn timing)
	unixTime: () -> number, -- sim.collection first-time stamps
	getProfile: (userId: number) -> any, -- the loaded profile or nil
	isUnlocked: (userId: number, zone: number) -> boolean,
	addFindValue: (userId: number, value: number) -> (boolean, string?),
	log: (level: "info" | "warn", message: string) -> (),
}

export type Core = {
	addPoint: (key: any, zone: number, x: number, y: number, z: number, name: string) -> number,
	removePoint: (key: any) -> boolean,
	points: () -> { Point },
	activate: (userId: number) -> (),
	deactivate: (userId: number) -> (),
	isActive: (userId: number) -> boolean,
	step: (userId: number) -> number,
	spawnNow: (userId: number) -> number,
	roll: (userId: number, zone: number) -> (string, number?, string?, string?),
	findFor: (zone: number, rarity: string) -> string?,
	pickup: (userId: number, ball: Ball?, magnet: number, held: boolean) -> number,
	clearBall: (userId: number) -> (),
	forget: (userId: number) -> (),
	spawned: (userId: number) -> { Spawned },
	ballFinds: (userId: number) -> { string },
	setForce: (userId: number, force: Force?) -> (),
	subscribe: (listener: (event: Event) -> ()) -> () -> (),
}

local SECRET = "Secret"

local FindCore = {}

FindCore.Refusal = table.freeze({
	Locked = "Locked", -- the find's zone is not unlocked for this player
	NotHeld = "NotHeld", -- the owner is not at the ball
	NotLoaded = "NotLoaded",
	NoFind = "NoFind", -- this world has no find of the rolled rarity
})

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The ball effect a profile's titles give (Config.Finds.BallEffects), or nil.
function FindCore.ballEffectOf(config: any, profile: any): string?
	local sim = type(profile) == "table" and profile.sim or nil
	local titles = type(sim) == "table" and sim.titles or nil
	if type(titles) ~= "table" then
		return nil
	end
	local best: string? = nil
	local bestTitle: string? = nil
	for title, effect in config.BallEffects do
		-- Sorted by title, so two effects always resolve the same way.
		if titles[title] == true and (bestTitle == nil or title < bestTitle) then
			best, bestTitle = effect, title
		end
	end
	return best
end

-- Gap between a ball's surface and a point; <= 0 when the point is inside the ball.
function FindCore.gap(ball: Ball, point: Point): number
	local dx, dy, dz = ball.x - point.x, ball.y - point.y, ball.z - point.z
	return math.sqrt(dx * dx + dy * dy + dz * dz) - ball.radius
end

function FindCore.new(deps: Deps): Core
	local config = deps.config
	local byKey: { [any]: Point } = {}
	local bySlot: { [number]: Point } = {}
	local order: { Point } = {}
	local nextSlot = 0

	type UserState = {
		active: boolean,
		spawned: { [number]: Spawned },
		emptySince: { [number]: number },
		ball: { string },
		lastRefused: { [number]: string },
	}
	local users: { [number]: UserState } = {}
	local forces: { [number]: Force } = {}
	local listeners: { (event: Event) -> () } = {}
	local warnedWorlds: { [string]: boolean } = {}

	local function emit(event: Event)
		for _, listener in table.clone(listeners) do
			local ok, message = pcall(listener, event)
			if not ok then
				deps.log("warn", `find listener failed: {tostring(message)}`)
			end
		end
	end

	local function stateOf(userId: number): UserState
		local state = users[userId]
		if state == nil then
			state = { active = false, spawned = {}, emptySince = {}, ball = {}, lastRefused = {} }
			users[userId] = state
		end
		return state
	end

	local function rebuildOrder()
		order = {}
		for _, point in bySlot do
			table.insert(order, point)
		end
		table.sort(order, function(a, b)
			return a.slot < b.slot
		end)
	end

	local function addPoint(key: any, zone: number, x: number, y: number, z: number, name: string): number
		local existing = byKey[key]
		if existing then
			return existing.slot
		end
		nextSlot += 1
		local point: Point = { slot = nextSlot, key = key, zone = zone, x = x, y = y, z = z, name = name }
		byKey[key] = point
		bySlot[point.slot] = point
		table.insert(order, point)
		local now = deps.now()
		for _, state in users do
			if state.active then
				state.emptySince[point.slot] = now
			end
		end
		return point.slot
	end

	local function removePoint(key: any): boolean
		local point = byKey[key]
		if point == nil then
			return false
		end
		byKey[key] = nil
		bySlot[point.slot] = nil
		rebuildOrder()
		for userId, state in users do
			state.emptySince[point.slot] = nil
			state.lastRefused[point.slot] = nil
			if state.spawned[point.slot] then
				state.spawned[point.slot] = nil
				emit({ kind = "Remove", userId = userId, slot = point.slot, reason = "PointRemoved" })
			end
		end
		return true
	end

	-- The find id for a rarity in a zone: the world's find, or the secret find in every world.
	local function findFor(zone: number, rarity: string): string?
		if rarity == SECRET then
			return config.SecretFind
		end
		local world = deps.worldOf(zone)
		local catalogue = config.ByWorld[world]
		local id = catalogue and catalogue[rarity]
		if id == nil then
			local key = `{world}:{rarity}`
			if not warnedWorlds[key] then
				warnedWorlds[key] = true
				deps.log("warn", `world {world} has no {rarity} find in Config.Finds.ByWorld, nothing spawns`)
			end
		end
		return id
	end

	local function hasRarity(entries: { { id: string, weight: number } }, rarity: string): boolean
		for _, entry in entries do
			if entry.id == rarity and entry.weight > 0 then
				return true
			end
		end
		return false
	end

	-- Rarity, the roll used (nil when forced), how it was forced, and a forced rarity that this
	-- zone's table refuses (then the normal roll decides: a switch never breaks the zone rule).
	local function roll(userId: number, zone: number): (string, number?, string?, string?)
		local entries = deps.findOdds(zone)
		local force = forces[userId]
		local refused: string? = nil
		if force and force.rarity ~= nil then
			if hasRarity(entries, force.rarity) then
				return force.rarity, nil, "Rarity", nil
			end
			refused = force.rarity
		end
		if force and force.roll ~= nil then
			return deps.pick(entries, force.roll), force.roll, "Roll", refused
		end
		local value = deps.generator.next()
		return deps.pick(entries, value), value, nil, refused
	end

	local function spawnAt(userId: number, state: UserState, point: Point, now: number): boolean
		local rarity, value, forced, refused = roll(userId, point.zone)
		local findId = findFor(point.zone, rarity)
		if findId == nil then
			state.emptySince[point.slot] = now
			emit({
				kind = "Refused",
				userId = userId,
				slot = point.slot,
				zone = point.zone,
				refusal = FindCore.Refusal.NoFind,
			})
			return false
		end
		local spawned: Spawned = {
			slot = point.slot,
			findId = findId,
			rarity = rarity,
			zone = point.zone,
			roll = value,
			forced = forced,
			at = now,
		}
		state.spawned[point.slot] = spawned
		state.emptySince[point.slot] = nil
		state.lastRefused[point.slot] = nil
		emit({
			kind = "Spawn",
			userId = userId,
			slot = point.slot,
			findId = findId,
			rarity = rarity,
			zone = point.zone,
			point = point,
			roll = value,
			forced = forced,
			forceRefused = refused,
		})
		return true
	end

	local function activate(userId: number)
		local state = stateOf(userId)
		state.spawned = {}
		state.emptySince = {}
		state.lastRefused = {}
		state.active = true
		local now = deps.now()
		for _, point in order do
			state.emptySince[point.slot] = now
		end
		emit({ kind = "Reset", userId = userId, reason = "Activate" })
	end

	-- Spawned finds go; the finds in the ball stay with the ball (the sale or leaving ends them).
	local function deactivate(userId: number)
		local state = users[userId]
		if state == nil or not state.active then
			return
		end
		state.active = false
		state.spawned = {}
		state.emptySince = {}
		state.lastRefused = {}
		emit({ kind = "Reset", userId = userId, reason = "Deactivate" })
	end

	local function step(userId: number): number
		local state = users[userId]
		if state == nil or not state.active or deps.getProfile(userId) == nil then
			return 0
		end
		local now = deps.now()
		local count = 0
		for _, point in order do
			if state.spawned[point.slot] == nil then
				local since = state.emptySince[point.slot]
				if since == nil then
					state.emptySince[point.slot] = now
				elseif now - since >= config.SpawnInterval then
					if spawnAt(userId, state, point, now) then
						count += 1
					end
				end
			end
		end
		return count
	end

	-- Studio (FindRespawnNow): every spawned find goes and every point gets a new one now.
	local function spawnNow(userId: number): number
		local state = users[userId]
		if state == nil or not state.active or deps.getProfile(userId) == nil then
			return 0
		end
		local now = deps.now()
		for _, point in order do
			if state.spawned[point.slot] then
				state.spawned[point.slot] = nil
				emit({ kind = "Remove", userId = userId, slot = point.slot, reason = "Respawn" })
			end
		end
		local count = 0
		for _, point in order do
			if spawnAt(userId, state, point, now) then
				count += 1
			end
		end
		return count
	end

	-- sim.collection.finds[findId] = first time, and the secret find's title. Malformed tables
	-- are left alone, never repaired (ADR 0006); the find still counts in the ball.
	local function record(profile: any, findId: string, rarity: string): (boolean?, string?, boolean?, string?)
		local sim = type(profile) == "table" and profile.sim or nil
		local collection = type(sim) == "table" and sim.collection or nil
		local finds = type(collection) == "table" and collection.finds or nil
		if type(finds) ~= "table" then
			return nil, nil, nil, "sim.collection.finds is not a table"
		end
		local first = finds[findId] == nil
		if first then
			finds[findId] = deps.unixTime()
		end
		if rarity ~= SECRET then
			return first, nil, nil, nil
		end
		local title = config.SecretTitle
		local titles = sim.titles
		if type(titles) ~= "table" then
			return first, nil, nil, "sim.titles is not a table"
		end
		local newTitle = titles[title] ~= true
		titles[title] = true
		return first, title, newTitle, nil
	end

	local function collect(userId: number, state: UserState, spawned: Spawned, profile: any)
		local now = deps.now()
		state.spawned[spawned.slot] = nil
		state.emptySince[spawned.slot] = now
		state.lastRefused[spawned.slot] = nil
		local value = if spawned.rarity == SECRET then 0 else deps.findValue(spawned.zone, spawned.rarity)
		local ok, valueRefusal = deps.addFindValue(userId, value)
		if not ok then
			deps.log("warn", `user {userId}: find {spawned.findId} value {value} refused: {tostring(valueRefusal)}`)
		end
		local first, title, newTitle, problem = record(profile, spawned.findId, spawned.rarity)
		if problem then
			deps.log("warn", `user {userId}: find {spawned.findId} not recorded: {problem}`)
		end
		table.insert(state.ball, spawned.findId)
		emit({
			kind = "Collect",
			userId = userId,
			slot = spawned.slot,
			findId = spawned.findId,
			rarity = spawned.rarity,
			zone = spawned.zone,
			point = bySlot[spawned.slot],
			value = if ok then value else 0,
			valueRefusal = if ok then nil else valueRefusal,
			first = first,
			title = title,
			newTitle = newTitle,
			collectionProblem = problem,
		})
	end

	local function refuseOnce(userId: number, state: UserState, spawned: Spawned, refusal: string)
		if state.lastRefused[spawned.slot] == refusal then
			return
		end
		state.lastRefused[spawned.slot] = refusal
		emit({
			kind = "Refused",
			userId = userId,
			slot = spawned.slot,
			findId = spawned.findId,
			zone = spawned.zone,
			refusal = refusal,
		})
	end

	local function pickup(userId: number, ball: Ball?, magnet: number, held: boolean): number
		local state = users[userId]
		if state == nil or not state.active or ball == nil then
			return 0
		end
		local profile = deps.getProfile(userId)
		if profile == nil then
			return 0
		end
		if not (isFinite(ball.x) and isFinite(ball.y) and isFinite(ball.z) and isFinite(ball.radius)) then
			return 0
		end
		local reach = if isFinite(magnet) and magnet > 0 then magnet else 0
		local count = 0
		for _, point in order do
			local spawned = state.spawned[point.slot]
			if spawned and FindCore.gap(ball, point) <= reach then
				if not held then
					refuseOnce(userId, state, spawned, FindCore.Refusal.NotHeld)
				elseif not deps.isUnlocked(userId, spawned.zone) then
					refuseOnce(userId, state, spawned, FindCore.Refusal.Locked)
				else
					collect(userId, state, spawned, profile)
					count += 1
				end
			end
		end
		return count
	end

	local function clearBall(userId: number)
		local state = stateOf(userId)
		state.ball = {}
		emit({ kind = "ClearBall", userId = userId })
	end

	return table.freeze({
		addPoint = addPoint,
		removePoint = removePoint,
		points = function(): { Point }
			return table.clone(order)
		end,
		activate = activate,
		deactivate = deactivate,
		isActive = function(userId: number): boolean
			local state = users[userId]
			return state ~= nil and state.active
		end,
		step = step,
		spawnNow = spawnNow,
		roll = roll,
		findFor = findFor,
		pickup = pickup,
		clearBall = clearBall,
		forget = function(userId: number)
			users[userId] = nil
			forces[userId] = nil
		end,
		spawned = function(userId: number): { Spawned }
			local state = users[userId]
			local list: { Spawned } = {}
			if state then
				for _, point in order do
					local spawned = state.spawned[point.slot]
					if spawned then
						table.insert(list, spawned)
					end
				end
			end
			return list
		end,
		ballFinds = function(userId: number): { string }
			local state = users[userId]
			return if state then table.clone(state.ball) else {}
		end,
		setForce = function(userId: number, force: Force?)
			forces[userId] = force
		end,
		subscribe = function(listener: (event: Event) -> ()): () -> ()
			table.insert(listeners, listener)
			return function()
				local index = table.find(listeners, listener)
				if index then
					table.remove(listeners, index)
				end
			end
		end,
	})
end

return table.freeze(FindCore)

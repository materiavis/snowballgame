--!strict
-- The group chest rule (concept 7.1, 6.5; ADR 0015): members of the Materiavis group open it
-- once per player and get GroupChestCoins and GroupChestSnowCoins. Pure: profile, membership,
-- currency and save are injected, so a headless spec runs it against DataCore and the fake
-- store.
--
-- Exactly once: `groupChestClaimed` and both balances live in the same profile, and the flag is
-- set and both grants are made without a yield in between. Any later save stores all three or
-- none, so a failed save, a crash or a rejoin can never pay twice or keep the flag without the
-- coins. The immediate save after the grant only shortens the window in which a crash loses it.
--
-- Outcomes: Opened, AlreadyOpened, NotMember, NoGroup, TryLater, NotReady, TooFar, Busy, Cooldown.

export type Membership = "Member" | "NotMember" | "NoGroup" | "Error"

export type Deps = {
	coins: number,
	snowCoins: number,
	cooldown: number,
	reach: number,
	now: () -> number,
	getProfile: (userId: number) -> any,
	-- May yield (a web call). Answers for this player.
	membership: (userId: number) -> Membership,
	addCoins: (userId: number, amount: number) -> boolean,
	addSnowCoins: (userId: number, amount: number) -> boolean,
	-- Called right after the grant, before the save, so the player sees the reward at once even
	-- when the save takes its retries.
	granted: ((userId: number) -> ())?,
	-- Yields; true once stored.
	save: (userId: number) -> boolean,
	log: (message: string) -> (),
}

export type Result = { outcome: string, saved: boolean? }

local ChestCore = {}

local REFUSED_BY_MEMBERSHIP: { [string]: string } = {
	NotMember = "NotMember",
	NoGroup = "NoGroup",
	Error = "TryLater",
}

local function isClaimed(profile: any): boolean
	return profile.groupChestClaimed == true
end

function ChestCore.new(deps: Deps)
	local busy: { [number]: boolean } = {}
	local lastTry: { [number]: number } = {}
	local core = {}

	-- One open attempt. `distance` is the server's distance from the character to the chest.
	function core.open(userId: number, distance: number): Result
		if busy[userId] then
			return { outcome = "Busy" }
		end
		local now = deps.now()
		local last = lastTry[userId]
		if last ~= nil and now - last < deps.cooldown then
			return { outcome = "Cooldown" }
		end
		lastTry[userId] = now
		if type(distance) ~= "number" or distance ~= distance or distance > deps.reach then
			return { outcome = "TooFar" }
		end
		local profile = deps.getProfile(userId)
		if profile == nil then
			return { outcome = "NotReady" }
		end
		if isClaimed(profile) then
			return { outcome = "AlreadyOpened" }
		end

		busy[userId] = true
		local ok, membership = pcall(deps.membership, userId)
		if not ok then
			deps.log(`membership check for {userId} errored: {membership}`)
			membership = "Error"
		end
		local refused = REFUSED_BY_MEMBERSHIP[membership]
		if refused then
			busy[userId] = nil
			return { outcome = refused }
		end

		-- The membership check yielded: the session may have ended or another path claimed.
		profile = deps.getProfile(userId)
		if profile == nil then
			busy[userId] = nil
			return { outcome = "NotReady" }
		end
		if isClaimed(profile) then
			busy[userId] = nil
			return { outcome = "AlreadyOpened" }
		end

		profile.groupChestClaimed = true
		if not deps.addCoins(userId, deps.coins) then
			-- Nothing was given, so the chest stays closed for a later try.
			profile.groupChestClaimed = false
			busy[userId] = nil
			deps.log(`coins for {userId} refused; chest stays closed`)
			return { outcome = "TryLater" }
		end
		if not deps.addSnowCoins(userId, deps.snowCoins) then
			-- The coins are given and stay given with the flag; never pay the coins twice.
			deps.log(`snow coins for {userId} refused after the coins; chest stays opened`)
		end
		if deps.granted then
			deps.granted(userId)
		end
		local saved = deps.save(userId)
		busy[userId] = nil
		return { outcome = "Opened", saved = saved }
	end

	function core.forget(userId: number)
		busy[userId] = nil
		lastTry[userId] = nil
	end

	return table.freeze(core)
end

return table.freeze(ChestCore)

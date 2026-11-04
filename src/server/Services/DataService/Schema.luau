--!strict
-- Save format v1 (ADR 0003 "Data model and failure behaviour"): defaults for a new player,
-- plus the step that turns a stored profile into one the current code can use.
-- Pure, no requires: the config is passed in, so `lune run tests` loads it.
--
-- Not saved on purpose (concept 6.5): ball size and the finds currently in the ball. Finds
-- reach the profile through sim.collection the moment they are picked up.
--
-- DataStores only store JSON: dictionaries need string keys, so sets keyed by zone, find or
-- pet id use string keys ("1", "IceCube"). A table with number keys must be a plain array.

local VERSION = 1

-- Migrations from version N to N + 1, keyed by N. Empty while v1 is the only format; every
-- later format change adds one step here and is escalated to the owners (CLAUDE.md §13).
local MIGRATIONS: { [number]: (data: { [string]: any }) -> () } = {}

export type Profile = { [string]: any }

export type Schema = {
	VERSION: number,
	newProfile: () -> Profile,
	prepare: (data: any) -> (Profile?, string?),
}

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[key] = copy(inner)
	end
	return out
end

-- Adds keys that exist in the defaults but not in the stored data. An empty default table is
-- a map (pets, finds, receipts, ...), so its stored contents are left alone.
local function fillMissing(data: { [any]: any }, defaults: { [any]: any })
	for key, default in defaults do
		local stored = data[key]
		if stored == nil then
			data[key] = copy(default)
		elseif type(default) == "table" and type(stored) == "table" and next(default) ~= nil then
			fillMissing(stored, default)
		end
	end
end

local Schema = {}

Schema.VERSION = VERSION

function Schema.new(config: { InventorySize: number }): Schema
	local function newProfile(): Profile
		return {
			schemaVersion = VERSION,
			settings = {
				music = true,
				sound = true,
				graphics = true,
				fewerEffects = false,
				tradeRequests = "all", -- "all" | "friends" | "off"
			},
			tutorial = {
				seenSingleArrow = false,
				seenMultiArrow = false,
				hints = {}, -- [hintId] = true
				firstMatchHints = false,
			},
			groupChestClaimed = false,
			lastMode = "", -- "" until the first mode is played
			boosts = {}, -- [boostId] = remaining seconds
			sim = {
				coins = 0,
				totalCoins = 0,
				upgrades = { growth = 0, walkSpeed = 0, magnet = 0, sellValue = 0, stability = 0 },
				unlockedZones = { ["1"] = true }, -- set, string zone ids
				lastWorld = 1,
				lastZone = 1,
				highestZone = 1,
				rebirths = 0,
				pets = {}, -- [uid] = { kind, variant, frosty, equipped }
				inventorySize = config.InventorySize,
				collection = { finds = {}, pets = {}, zones = {} }, -- [id] = first time (unix s)
				records = { biggestBall = 0, mostCoinsInOneBall = 0 },
				titles = {}, -- [titleId] = true
				stats = {}, -- [counter] = number
				daily = { streakDay = 0, lastClaimDay = 0 }, -- UTC day index, 0 = never
				ballSkins = {}, -- [skinId] = true
				starterPackBought = false,
				tradeHistory = {}, -- array, newest last, at most Config.Data.TradeHistorySize
				pendingTradeId = "", -- "" = no trade in flight
			},
			fight = {
				snowCoins = 0,
				xp = 0,
				level = 1,
				wins = 0,
				losses = 0,
				freezes = 0,
				cosmetics = { owned = {}, equipped = {} }, -- owned: set; equipped: [slot] = id
			},
			purchases = {
				receipts = {}, -- [PurchaseId] = unix s, at most Config.Data.ReceiptsKept
			},
		}
	end

	-- Returns nil and a reason when the stored value must not be used. The caller then treats
	-- the load as failed and never writes over it (a newer server may have written it).
	local function prepare(data: any): (Profile?, string?)
		if type(data) ~= "table" then
			return nil, "profile is not a table"
		end
		local version = data.schemaVersion
		if type(version) ~= "number" or version < 1 or version % 1 ~= 0 then
			return nil, `invalid schemaVersion {tostring(version)}`
		end
		if version > VERSION then
			return nil, `schemaVersion {version} is newer than this server ({VERSION})`
		end
		while data.schemaVersion < VERSION do
			local step = MIGRATIONS[data.schemaVersion]
			if step == nil then
				return nil, `no migration from schemaVersion {data.schemaVersion}`
			end
			step(data)
			data.schemaVersion += 1
		end
		fillMissing(data, newProfile())
		return data, nil
	end

	return table.freeze({
		VERSION = VERSION,
		newProfile = newProfile,
		prepare = prepare,
	})
end

return table.freeze(Schema)

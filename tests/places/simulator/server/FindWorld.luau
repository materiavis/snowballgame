--!strict
-- Builds a FindCore on the real Config.Finds, Rng odds, Formulas.Economy.findValue and a
-- schema v1 profile, with a FakeClock and a seeded generator. Not a spec: the runner only loads
-- *.spec.luau. Specs replace getProfile / addFindValue to run against the fake store or SellCore.

local E = require("../../../helpers/Economy")
local FakeClock = require("../../../helpers/FakeClock")
local SeededRandom = require("../../../helpers/SeededRandom")
local DataConfig = require("../../../../src/shared/Config/Data")
local Schema = require("../../../../src/server/Services/DataService/Schema")
local FindCore = require("../../../../src/places/simulator/server/FindService/FindCore")

export type Options = {
	seed: number?,
	getProfile: ((userId: number) -> any)?,
	addFindValue: ((userId: number, value: number) -> (boolean, string?))?,
	unixTime: number?,
}

export type World = {
	core: FindCore.Core,
	clock: FakeClock.FakeClock,
	events: { FindCore.Event },
	profiles: { [number]: any },
	loaded: { [number]: boolean },
	unlocked: { [number]: boolean },
	added: { { userId: number, value: number } },
	logs: { string },
}

local FindWorld = {}

FindWorld.USER = 1001
FindWorld.OTHER = 1002
FindWorld.UNIX = 1_800_000_000
FindWorld.Config = E.Config.Finds
FindWorld.E = E

function FindWorld.new(options: Options?): World
	local opts: Options = options or {}
	local w: World = {
		core = nil :: any,
		clock = FakeClock.new(100),
		events = {},
		profiles = {},
		loaded = {},
		unlocked = { [1] = true },
		added = {},
		logs = {},
	}
	local schema = Schema.new(DataConfig)
	for _, userId in { FindWorld.USER, FindWorld.OTHER } do
		w.profiles[userId] = schema.newProfile()
		w.loaded[userId] = true
	end
	w.core = FindCore.new({
		config = E.Config.Finds,
		findOdds = E.Odds.findOdds,
		pick = E.Weighted.pick,
		findValue = E.Economy.findValue,
		worldOf = E.Zones.worldOf,
		generator = SeededRandom.new(opts.seed or 40),
		now = w.clock.now,
		unixTime = function(): number
			return opts.unixTime or FindWorld.UNIX
		end,
		getProfile = opts.getProfile or function(userId: number): any
			return if w.loaded[userId] then w.profiles[userId] else nil
		end,
		isUnlocked = function(_userId: number, zone: number): boolean
			return w.unlocked[zone] == true
		end,
		addFindValue = opts.addFindValue or function(userId: number, value: number): (boolean, string?)
			table.insert(w.added, { userId = userId, value = value })
			return true, nil
		end,
		log = function(level: string, message: string)
			table.insert(w.logs, `{level}: {message}`)
		end,
	})
	w.core.subscribe(function(event: FindCore.Event)
		table.insert(w.events, event)
	end)
	return w
end

-- Events of one kind (and user) since the start.
function FindWorld.of(w: World, kind: string, userId: number?): { FindCore.Event }
	local list = {}
	for _, event in w.events do
		if event.kind == kind and (userId == nil or event.userId == userId) then
			table.insert(list, event)
		end
	end
	return list
end

-- A ball resting on a point: its centre one radius above the point.
function FindWorld.ballOn(point: FindCore.Point, radius: number): FindCore.Ball
	return { x = point.x, y = point.y + radius, z = point.z, radius = radius }
end

return table.freeze(FindWorld)

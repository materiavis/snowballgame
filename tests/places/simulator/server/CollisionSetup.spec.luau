--!strict
-- Ball collision groups (issue #33 AC5, ADR 0003 rev. 2): the rule table in Config.Ball is
-- exactly the ADR table, and CollisionSetup registers and applies it on a fake PhysicsService
-- that behaves like Roblox (new groups collide with everything until told otherwise).

local T = require("../../../TestKit")
local BallConfig = require("../../../../src/shared/Config/Ball")
local CollisionSetup = require("../../../../src/places/simulator/server/BallService/CollisionSetup")

local function pairKey(a: string, b: string): string
	if a > b then
		a, b = b, a
	end
	return `{a}|{b}`
end

local function fakePhysics()
	local registered: { [string]: boolean } = { Default = true }
	local blocked: { [string]: boolean } = {}
	local registrations = 0
	local physics = {
		isRegistered = function(name: string): boolean
			return registered[name] == true
		end,
		register = function(name: string)
			assert(not registered[name], `{name} registered twice`)
			registered[name] = true
			registrations += 1
		end,
		setCollidable = function(a: string, b: string, collides: boolean)
			assert(registered[a] and registered[b], `unregistered group in {a}/{b}`)
			blocked[pairKey(a, b)] = not collides
		end,
		areCollidable = function(a: string, b: string): boolean
			return not blocked[pairKey(a, b)]
		end,
	}
	return physics, function(): number
		return registrations
	end
end

-- ADR 0003 rev. 2, "Ball collisions with foreign characters", then the OtherCharacters
-- extension of ADR 0002 (concept 7.3 ✅: nobody can block anyone).
local ADR_TABLE = {
	{ "OwnCharacter", "OwnBall", true },
	{ "OwnCharacter", "Balls", false },
	{ "OwnBall", "Balls", false },
	{ "Balls", "Balls", false },
	{ "OwnCharacter", "Default", true },
	{ "OwnBall", "Default", true },
	{ "Balls", "Default", true },
	{ "OwnBall", "OtherCharacters", false },
	{ "OwnCharacter", "OtherCharacters", false },
	{ "Balls", "OtherCharacters", false },
	{ "OtherCharacters", "OtherCharacters", false },
	{ "OtherCharacters", "Default", true },
}

return T.suite("Simulator ball collision groups (ADR 0003 rev. 2 + ADR 0002)", function(test)
	test("the config holds exactly the four global groups", function()
		local names = {}
		for key, name in BallConfig.CollisionGroups do
			T.equal(key, name, "key and group name match")
			table.insert(names, name)
		end
		table.sort(names)
		T.equal(table.concat(names, ","), "Balls,OtherCharacters,OwnBall,OwnCharacter")
	end)

	test("the own ball collides only with the own character and the world", function()
		local physics = fakePhysics()
		CollisionSetup.apply(physics, BallConfig.CollisionGroups, BallConfig.CollisionRules)
		local g = BallConfig.CollisionGroups
		T.equal(physics.areCollidable(g.OwnBall, g.OwnCharacter), true, "own character")
		T.equal(physics.areCollidable(g.OwnBall, "Default"), true, "world")
		T.equal(physics.areCollidable(g.OwnBall, g.OtherCharacters), false, "foreign characters cannot block it")
		T.equal(physics.areCollidable(g.OwnBall, g.Balls), false, "foreign balls")
		T.equal(physics.areCollidable(g.OwnCharacter, g.OtherCharacters), false, "nobody blocks anyone")
		T.equal(physics.areCollidable(g.OwnCharacter, g.Balls), false, "walk through foreign balls")
		T.equal(physics.areCollidable(g.OtherCharacters, "Default"), true, "foreign characters stand on the world")
	end)

	test("the config rules are the ADR table", function()
		T.equal(#BallConfig.CollisionRules, #ADR_TABLE, "rule count")
		for i, expected in ADR_TABLE do
			local rule = BallConfig.CollisionRules[i]
			T.equal(rule[1], expected[1], `rule {i} group A`)
			T.equal(rule[2], expected[2], `rule {i} group B`)
			T.equal(rule[3], expected[3], `rule {i} collides`)
		end
	end)

	test("apply registers the groups and every rule holds afterwards", function()
		local physics, registrations = fakePhysics()
		CollisionSetup.apply(physics, BallConfig.CollisionGroups, BallConfig.CollisionRules)
		T.equal(registrations(), 4, "four groups registered")
		local ok, text = CollisionSetup.check(physics, BallConfig.CollisionRules)
		T.isTrue(ok, text)
		T.isTrue(string.find(text, "OwnCharacter<->Balls=false", 1, true) ~= nil, text)
		-- Pairs the table does not name keep the engine default: own character with itself.
		T.isTrue(physics.areCollidable("OwnCharacter", "OwnCharacter"))
	end)

	test("apply twice is harmless", function()
		local physics, registrations = fakePhysics()
		CollisionSetup.apply(physics, BallConfig.CollisionGroups, BallConfig.CollisionRules)
		CollisionSetup.apply(physics, BallConfig.CollisionGroups, BallConfig.CollisionRules)
		T.equal(registrations(), 4)
		T.isTrue((CollisionSetup.check(physics, BallConfig.CollisionRules)))
	end)

	test("fromPhysicsService forwards to the PhysicsService methods", function()
		local physics = fakePhysics()
		local calls = {}
		local service = {
			IsCollisionGroupRegistered = function(_self, name)
				table.insert(calls, `is:{name}`)
				return physics.isRegistered(name)
			end,
			RegisterCollisionGroup = function(_self, name)
				table.insert(calls, `reg:{name}`)
				physics.register(name)
			end,
			CollisionGroupSetCollidable = function(_self, a, b, collides)
				physics.setCollidable(a, b, collides)
			end,
			CollisionGroupsAreCollidable = function(_self, a, b)
				return physics.areCollidable(a, b)
			end,
		}
		local wrapped = CollisionSetup.fromPhysicsService(service)
		CollisionSetup.apply(wrapped, BallConfig.CollisionGroups, BallConfig.CollisionRules)
		T.isTrue((CollisionSetup.check(wrapped, BallConfig.CollisionRules)))
		T.equal(
			table.concat(calls, ","),
			"is:Balls,reg:Balls,is:OtherCharacters,reg:OtherCharacters,is:OwnBall,reg:OwnBall,is:OwnCharacter,reg:OwnCharacter"
		)
	end)

	test("check reports a rule that does not hold", function()
		local physics = fakePhysics()
		CollisionSetup.apply(physics, BallConfig.CollisionGroups, BallConfig.CollisionRules)
		physics.setCollidable("OwnBall", "Balls", true)
		local ok, text = CollisionSetup.check(physics, BallConfig.CollisionRules)
		T.equal(ok, false)
		T.isTrue(string.find(text, "OwnBall<->Balls=true", 1, true) ~= nil, text)
	end)
end)

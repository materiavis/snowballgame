--!strict
-- Registers the ball collision groups and applies the rule table of ADR 0003 rev. 2 through
-- a PhysicsService-like interface. Pure, so `lune run tests` checks it against a fake.

export type Physics = {
	isRegistered: (name: string) -> boolean,
	register: (name: string) -> (),
	setCollidable: (a: string, b: string, collides: boolean) -> (),
	areCollidable: (a: string, b: string) -> boolean,
}

export type Rule = { any } -- { groupA: string, groupB: string, collides: boolean }

-- The engine's built-in group; it always exists and is never registered.
local DEFAULT_GROUP = "Default"

local CollisionSetup = {}

-- Wraps Roblox's PhysicsService (passed in, so this module stays loadable under Lune).
function CollisionSetup.fromPhysicsService(service: any): Physics
	return {
		isRegistered = function(name: string): boolean
			return service:IsCollisionGroupRegistered(name)
		end,
		register = function(name: string)
			service:RegisterCollisionGroup(name)
		end,
		setCollidable = function(a: string, b: string, collides: boolean)
			service:CollisionGroupSetCollidable(a, b, collides)
		end,
		areCollidable = function(a: string, b: string): boolean
			return service:CollisionGroupsAreCollidable(a, b)
		end,
	}
end

-- Registers every group that is not registered yet, then sets every rule. Running it twice
-- changes nothing, so a restarted service is harmless.
function CollisionSetup.apply(physics: Physics, groups: { [string]: string }, rules: { Rule })
	local names: { string } = {}
	for _, name in groups do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		if name ~= DEFAULT_GROUP and not physics.isRegistered(name) then
			physics.register(name)
		end
	end
	for _, rule in rules do
		physics.setCollidable(rule[1], rule[2], rule[3])
	end
end

-- Reads the rules back. Returns whether every rule holds and a text like
-- "OwnCharacter<->OwnBall=true ..." for the startup line.
function CollisionSetup.check(physics: Physics, rules: { Rule }): (boolean, string)
	local ok = true
	local parts: { string } = {}
	for _, rule in rules do
		local actual = physics.areCollidable(rule[1], rule[2])
		if actual ~= rule[3] then
			ok = false
		end
		table.insert(parts, `{rule[1]}<->{rule[2]}={actual}`)
	end
	return ok, table.concat(parts, " ")
end

return table.freeze(CollisionSetup)

--!strict
-- Pure obstacle rules for BallService (concept 7.4, ADR 0002): whether a ball touches a box
-- and what a set of touches means. No Instances, so `lune run tests` loads it.
--
-- A collision is a new touch. Pressing against the same tree is one collision, not one every
-- second, because the protection time would otherwise turn holding W into a steady drain.

export type ObstacleConfig = {
	CollisionContactMargin: number,
}

-- `obstacle` is opaque here (a BasePart in the game, a string in tests).
export type Contact = {
	obstacle: any,
	knockOverSize: any,
}

export type Outcome = {
	contacts: { [any]: boolean },
	knockOvers: { any },
	hit: boolean,
}

export type ObstacleRules = {
	boxDistance: (x: number, y: number, z: number, halfX: number, halfY: number, halfZ: number) -> number,
	isTouching: (distance: number, radius: number) -> boolean,
	evaluate: (
		previous: { [any]: boolean }?,
		current: { Contact },
		protected: boolean,
		canKnockOver: (obstacleSize: any) -> boolean
	) -> Outcome,
}

local ObstacleRulesModule = {}

function ObstacleRulesModule.new(config: ObstacleConfig): ObstacleRules
	-- Distance from a point in the box's own space to the box; 0 inside it.
	local function boxDistance(x: number, y: number, z: number, halfX: number, halfY: number, halfZ: number): number
		local dx = math.max(math.abs(x) - halfX, 0)
		local dy = math.max(math.abs(y) - halfY, 0)
		local dz = math.max(math.abs(z) - halfZ, 0)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	local function isTouching(distance: number, radius: number): boolean
		return distance <= radius + config.CollisionContactMargin
	end

	-- `previous` is nil on the first sample after the ball was placed: whatever it touches
	-- then was not rolled into, so it is remembered without any effect.
	local function evaluate(
		previous: { [any]: boolean }?,
		current: { Contact },
		protected: boolean,
		canKnockOver: (obstacleSize: any) -> boolean
	): Outcome
		local contacts: { [any]: boolean } = {}
		local knockOvers: { any } = {}
		local hit = false
		for _, contact in current do
			contacts[contact.obstacle] = true
			if previous ~= nil and not previous[contact.obstacle] then
				if canKnockOver(contact.knockOverSize) then
					table.insert(knockOvers, contact.obstacle)
				elseif not protected then
					hit = true
				end
			end
		end
		return { contacts = contacts, knockOvers = knockOvers, hit = hit }
	end

	return table.freeze({
		boxDistance = boxDistance,
		isTouching = isTouching,
		evaluate = evaluate,
	})
end

return table.freeze(ObstacleRulesModule)

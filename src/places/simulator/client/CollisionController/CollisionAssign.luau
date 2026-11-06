--!strict
-- Pure choice of the local collision group for a ball (ADR 0003 rev. 2): the own ball is in
-- OwnBall, every other ball in Balls. A ball without a valid owner counts as foreign, so a
-- broken attribute can never make a stranger's ball collide with the own character.

export type Groups = {
	OwnCharacter: string,
	OwnBall: string,
	Balls: string,
}

local CollisionAssign = {}

function CollisionAssign.groupForBall(ownerUserId: any, localUserId: number, groups: Groups): string
	if type(ownerUserId) == "number" and ownerUserId == localUserId then
		return groups.OwnBall
	end
	return groups.Balls
end

return table.freeze(CollisionAssign)

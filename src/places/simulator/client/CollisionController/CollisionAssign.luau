--!strict
-- Pure choice of the local collision groups (ADR 0003 rev. 2, extended in ADR 0002). The own
-- ball is in OwnBall and every other ball in Balls; the own character is in OwnCharacter and
-- every other character in OtherCharacters. A missing or broken owner counts as foreign, so
-- it can never make a stranger's ball or character collide like the own one.

export type Groups = {
	OwnCharacter: string,
	OwnBall: string,
	Balls: string,
	OtherCharacters: string,
}

local CollisionAssign = {}

local function isOwn(ownerUserId: any, localUserId: number): boolean
	return type(ownerUserId) == "number" and ownerUserId == localUserId
end

function CollisionAssign.groupForBall(ownerUserId: any, localUserId: number, groups: Groups): string
	return if isOwn(ownerUserId, localUserId) then groups.OwnBall else groups.Balls
end

function CollisionAssign.groupForCharacter(ownerUserId: any, localUserId: number, groups: Groups): string
	return if isOwn(ownerUserId, localUserId) then groups.OwnCharacter else groups.OtherCharacters
end

return table.freeze(CollisionAssign)

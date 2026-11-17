--!strict
-- Text form of the pet attributes the server writes on a player (ADR 0013): `PetInventory` for
-- the own pets window and `PetEquipped` for the followers every client draws. Pure.
--
-- Inventory: "<uid>:<kind>:<1|0>;..." (1 = equipped). Equipped: "<uid>:<kind>;...".
-- Uids and kinds are tokens of letters, digits, "_" and "-", so ":" and ";" never occur inside.
-- The server never reads these back; decoding skips anything malformed instead of failing.

export type Entry = { uid: string, kind: string, equipped: boolean }

local PetCodec = {}

local TOKEN = "^[%w_%-]+$"

function PetCodec.isToken(value: any): boolean
	return type(value) == "string" and string.match(value, TOKEN) ~= nil
end

-- Entries whose uid or kind is not a token are left out (they could not be decoded).
function PetCodec.encodeInventory(entries: { Entry }): string
	local parts = {}
	for _, entry in entries do
		if PetCodec.isToken(entry.uid) and PetCodec.isToken(entry.kind) then
			table.insert(parts, `{entry.uid}:{entry.kind}:{if entry.equipped then "1" else "0"}`)
		end
	end
	return table.concat(parts, ";")
end

function PetCodec.encodeEquipped(entries: { Entry }): string
	local parts = {}
	for _, entry in entries do
		if PetCodec.isToken(entry.uid) and PetCodec.isToken(entry.kind) then
			table.insert(parts, `{entry.uid}:{entry.kind}`)
		end
	end
	return table.concat(parts, ";")
end

local function split(text: string, separator: string): { string }
	local parts = {}
	for part in string.gmatch(text, `[^{separator}]+`) do
		table.insert(parts, part)
	end
	return parts
end

function PetCodec.decodeInventory(value: any): { Entry }
	local entries: { Entry } = {}
	if type(value) ~= "string" then
		return entries
	end
	for _, item in split(value, ";") do
		local fields = split(item, ":")
		local flag = fields[3]
		if
			#fields == 3
			and PetCodec.isToken(fields[1])
			and PetCodec.isToken(fields[2])
			and (flag == "0" or flag == "1")
		then
			table.insert(entries, { uid = fields[1], kind = fields[2], equipped = flag == "1" })
		end
	end
	return entries
end

function PetCodec.decodeEquipped(value: any): { Entry }
	local entries: { Entry } = {}
	if type(value) ~= "string" then
		return entries
	end
	for _, item in split(value, ";") do
		local fields = split(item, ":")
		if #fields == 2 and PetCodec.isToken(fields[1]) and PetCodec.isToken(fields[2]) then
			table.insert(entries, { uid = fields[1], kind = fields[2], equipped = true })
		end
	end
	return entries
end

return table.freeze(PetCodec)

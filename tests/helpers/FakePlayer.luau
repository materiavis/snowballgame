--!strict
-- A Player stand-in for attribute specs: SetAttribute/GetAttribute on a plain table. Setting nil
-- removes the attribute, as on Roblox. `names()` lists the attributes that are set, sorted.

export type FakePlayer = {
	UserId: number,
	SetAttribute: (self: FakePlayer, name: string, value: any) -> (),
	GetAttribute: (self: FakePlayer, name: string) -> any,
	names: () -> { string },
}

local FakePlayer = {}

function FakePlayer.new(userId: number): FakePlayer
	local attributes: { [string]: any } = {}
	local player = {} :: FakePlayer
	player.UserId = userId
	function player.SetAttribute(_self: FakePlayer, name: string, value: any)
		attributes[name] = value
	end
	function player.GetAttribute(_self: FakePlayer, name: string): any
		return attributes[name]
	end
	function player.names(): { string }
		local out = {}
		for name in attributes do
			table.insert(out, name)
		end
		table.sort(out)
		return out
	end
	return player
end

return table.freeze(FakePlayer)

--!strict
-- Studio stub for teleports at game.PlaceId == 0 (ADR 0003 "Teleports in Studio", ADR 0010).
-- Teleports and ReserveServer do not work in Studio, so this never touches TeleportService: it
-- logs one line per attempt with intent, origin, destination, server choice, zone and players,
-- and reports success or a simulated failure. Pure, no requires.

export type Deps = {
	print: (line: string) -> (),
	-- Studio switch: true makes this attempt fail like a teleport error.
	shouldFail: () -> boolean,
	describeTarget: (target: any) -> string,
}

local StubTeleporter = {}

function StubTeleporter.new(deps: Deps)
	local reserved = 0
	local stub = {}

	function stub.teleport(_userId: number, dest: any, target: any, info: any): (boolean, string?)
		local fail = deps.shouldFail()
		local destination = if dest.role == "Simulator"
			then `to=Simulator world={dest.world} zone={dest.zone}`
			else `to={dest.role}`
		local result = if fail then "simulated failure" else "ok"
		deps.print(
			`[TravelService] STUB teleport intent={info.intent} from={info.from} {destination} placeId={dest.placeId} server={deps.describeTarget(
				target
			)} players={info.players} attempt={info.attempt}/{info.attempts} -> {result}`
		)
		if fail then
			return false, "Simulated"
		end
		return true, nil
	end

	-- Fake access codes, numbered per server run, so the log shows a new reserved server.
	function stub.reserve(placeId: number): (boolean, string?, string?)
		reserved += 1
		deps.print(`[TravelService] STUB ReserveServer placeId={placeId} -> studio-reserved-{reserved}`)
		return true, `studio-reserved-{reserved}`, `studio-private-{reserved}`
	end

	return table.freeze(stub)
end

return table.freeze(StubTeleporter)

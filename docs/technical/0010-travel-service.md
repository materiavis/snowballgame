# 0010: TravelService, server selection and PresenceStore

**Status:** Accepted with merge of PR #NN.

Implements `x-travel-teleports` (#28) from [ADR 0003](0003-snow-rush-intake.md) (module table rows TravelService and PresenceStore, "Places, Rojo and world assets", "Live PlaceIds", "Teleports in Studio", Rules: Session locking → Teleport, Load failure, Cross-server ephemeral state) on top of DataService ([ADR 0006](0006-player-data.md) "Teleport", "Loading"), the Net layer ([ADR 0005](0005-net-remotes.md)) and the world gate rule of [ADR 0009](0009-map-contract.md). Concept 4.3 leaves teleport and matchmaking technique to Development; this records those choices.

## Context

Concept 5.6 and 6.5 fix the behaviour: every change of Place saves first; the Simulator is entered in the last visited zone on a server of that world with a free place, preferably a friend's; a full server means another server of that world or a new one; a failed teleport keeps the player in place with a short message and an automatic retry; a failed save keeps the player in place with a message. ADR 0003 adds that teleport data passes through the client and is never trusted, that MemoryStore is reached through one `PresenceStore` module, that every store is a fake at `game.PlaceId == 0`, and that players whose profile cannot be loaded outside the Lobby are sent back to it. Teleports do not work in Studio, so the stub must make each intent observable. The callers (portal #37, world gate #105, match start 7.14, Replay/To Lobby 7.15/7.21, Lobby button #90) do not exist yet.

## Decision

**Layout.** Both are folder modules in `src/server/Services`. Only the `init.luau` files touch Roblox services; the children are pure (no requires), so `lune run tests` loads them, as in DataService.

| Module | Role |
|---|---|
| `TravelService/init` | Wires Roblox: DataService, NetService, PresenceStore, the teleporter, Studio tools. Public API below. |
| `TravelService/TravelCore` | Flow per player: checks, save + release, teleport, resume, retry, messages, events. |
| `TravelService/LoadFailReturn` | Load failure outside the Lobby → back to the Lobby. Shares TravelCore's busy flags. |
| `TravelService/Destinations` | Intent → destination Place, world, zone, PlaceId; which intents are valid from which Place. |
| `TravelService/ServerChoice` | Public / friend's server / reserved server. |
| `TravelService/StubTeleporter` | PlaceId 0: logs and reports success or a simulated failure. Never touches TeleportService. |
| `TravelService/RealTeleporter` | `TeleportAsync` + `TeleportInitFailed`, `ReserveServer`. Gets TeleportService passed in. |
| `TravelService/StudioTools` | Studio switches (below). |
| `PresenceStore/init` | The only module that names MemoryStoreService. No `Start`, so the loader does not count it. |
| `PresenceStore/PresenceCore` | Presence and private mapping on one hash map, values validated on read. |
| `PresenceStore/FakeMemoryStore` | In-memory hash map with TTL, copies and fault injection. |
| `PresenceStore/StoreProvider` | Picks fake or real before MemoryStoreService is touched. |

All numbers are in `src/shared/Config/Travel.luau`; the Simulator server size is the existing `Config.Lobby.SimulatorPlayers` (10, concept 5.6/7.2), PlaceIds stay `0` placeholders in `Config.Places`.

**Intents and destinations.** Destinations come only from the current Place, `Config.Places` and the loaded profile, never from a client.

| Intent | From | To | Server |
|---|---|---|---|
| `Portal` | Lobby | Simulator `sim.lastWorld`, zone `sim.lastZone` | friend / public / private reserved |
| `WorldGate` | Simulator | next world, its first zone (`(world − 1) × ZonesPerWorld + 1`) | friend / public / private reserved |
| `LobbyButton` | Simulator | Lobby | public |
| `MatchStart` (group) | Lobby | Arena | the reserved server matchmaking passes (`accessCode`), else one new reserved server |
| `Replay` (group) | Arena | Arena | as `MatchStart` |
| `ToLobby` | Arena | Lobby | public |
| `LoadFailReturn` (internal) | Simulator, Arena | Lobby | public |

An invalid saved world (not listed in `Config.Places.Worlds`) falls back to World 1, a zone outside the world to its first zone; both are logged. The last world has no `WorldGate`. A live server refuses a destination whose PlaceId is `0` before saving, which also keeps the world gate closed while World 2 is unpublished (ADR 0009). TravelService does not write `sim.lastWorld`/`sim.lastZone`: ZoneService owns them (ADR 0003) and the destination places the player from the profile. No teleport data is sent.

**Flow per player (6.5).** Refused at once (logged, event `Refused`) if the intent is not valid from this Place, the player is already travelling, or the profile is not `Loaded` (message `NotReady`). Otherwise up to `TeleportAttempts` (3) attempts, each:
1. `DataService.PrepareTeleport` (save + release). `StoreError` is retried after `SaveRetryDelay` (5 s) up to `SaveAttempts` (2) with message `SaveRetry`; then `SaveFailed`, the player stays and keeps the lock. Any other refusal (`LockLost`, `Stale`, `Missing`) means DataService already kicked; no retry.
2. Teleport. Success is the player leaving. `TeleportAsync` throwing, `TeleportInitFailed`, or no result after `TeleportTimeout` (30 s) is a failure.
3. On failure `DataService.ResumeAfterTeleportFailure`. `false` with a store error is retried `ResumeAttempts` (3) times, `ResumeRetryDelay` apart; if the lock still cannot be taken back the player sees `ResumeFailed` and is kicked to rejoin (their state up to the save is stored and the lock is free). Any other `false` means the session is lost and DataService kicked; no retry.
4. `GameFull` on a friend's server switches the next attempt to public. Then message `TeleportRetry` and a backoff of `TeleportRetryBase × TeleportRetryFactor^(n−1)` capped at `TeleportRetryMax` (2, 4 s). After the last attempt `TeleportFailed`; the player stays with their lock.

Group intents check each player, refuse those that cannot go, choose one target for the rest and run each player's attempts in parallel (each saves on its own). Who replaces a player that does not arrive (bot after 15 s) is matchmaking's (7.14).

**Server choice.** Public teleports leave the choice to Roblox matchmaking, which picks a server of that Place with a free place and opens a new one when all are full; this is exactly 6.5 "Simulator-Server ist voll" and needs no server list of our own. **Humans must set the Simulator Places' `MaxPlayers` to `Config.Lobby.SimulatorPlayers` at publish.** Friend preference: `Player:GetFriendsOnline(FriendLookupMax)` gives the online friends; their presence entries in PresenceStore say which Simulator server of which world they are on; the first one in the destination world whose server record shows fewer than `SimulatorPlayers` players is used via `TeleportOptions.ServerInstanceId`. A friend lookup or MemoryStore failure only loses the preference. We use our own presence rather than the `GameId` from `GetFriendsOnline` because it also carries the server's player count, so a full friend server is skipped before trying.

**Private servers (ADR 0003 mapping, used by 9.4).** On a private (VIP) server the context key is `game.PrivateServerId`. Simulator destinations from there go to one reserved server per world: PresenceStore maps `private_<key>_<world>` → `{accessCode, privateServerId}` and `reserved_<privateServerId>` → key, TTL `PrivateMappingTtl` (1 day), so that reserved Simulator server finds its context again and its world gate leads into the same private chain. Private and reserved servers publish no presence (they cannot be joined by JobId). Coming back from a private Simulator to the *private* Lobby is not possible with a teleport (Roblox does not teleport into a private server by id); `LobbyButton` goes to a public Lobby. That is an open question for 9.4.

**PresenceStore.** One MemoryStore hash map `Presence`. Public Simulator servers publish `server_<jobId>` = `{world, count}` and `user_<userId>` = `{world, jobId}` every `PresenceRefresh` (30 s) with TTL `PresenceTtl` (60 s), remove a user on leave and the server on `BindToClose`. Losing it never loses progress. At PlaceId 0 `StoreProvider.select` builds `FakeMemoryStore.newService` and never calls `GetService("MemoryStoreService")`. Portal player counts (#37) and matchmaking (7.14) extend this module instead of opening their own.

**Load failure outside the Lobby (ADR 0003, ADR 0006).** `LoadFailReturn` counts `Failed` load statuses per player. After `LoadFailuresBeforeLobby` (2, each a full DataService load with its own retries, about a minute in total) it shows `LoadFailedReturn`, waits `LoadFailReturnDelay` (5 s) and, if the load still has not worked, teleports to the Lobby without `PrepareTeleport`: no lock is held, nothing is written. A load that recovers meanwhile cancels it. In the Lobby nothing happens (#35 shows the hint, #37 locks the portals).

**Remotes (ADR 0005).** `TravelRequestLobby` (client → server, no arguments, `Burst 2`, `0.5/s`): the destination is fixed, so a client can choose nothing; any argument is dropped as `Arity`; TravelCore refuses it outside the Simulator and while travelling. `TravelNotice` (server → client, a `Config.Travel.Messages` key; no handler, so client calls are dropped). The client shows only known keys. The example remote `NetExample` and `NetExampleService` are removed with this first real remote, as ADR 0005 and 0006 planned; `tests/shared/Net/Guard.spec.luau` keeps the same cases with a test-only declaration.

**Client.** `src/client/Controllers/TravelController` shows the message as a plain text label for `MessageSeconds` (owner decision 2026-11-10; #91 switches to the popup) and offers `TravelController.RequestLobby()` for the button of #90.

**Public API (server).** `TravelService.ToSimulator(player)` (portal), `ToNextWorld(player)` (world gate; the caller checks the gate is open), `ToLobby(player)` (after a match), `ToArena(players, accessCode?)`, `Replay(players, accessCode?)`, `RequestLobby(player)`, `Travel(player, intent, options?)` (yields, returns the outcome `Done`/`Refused`/`SaveFailed`/`TeleportFailed`/`Lost`/`Left`), `TravelGroup(players, intent, options?)` (`Started`/`Refused`), `IsTraveling(player)`.

### Studio stub and playtest support (PlaceId 0 and Studio only; live servers skip all of it)

At PlaceId 0 TeleportService is never fetched. Every attempt prints one line, for example:

```
[TravelService] Portal from=Lobby to=Simulator world=1 zone=1 placeId=0 server=Public players=Player1(-1)
[TravelService] STUB teleport intent=Portal from=Lobby to=Simulator world=1 zone=1 placeId=0 server=Public players=Player1(-1) attempt=1/3 -> ok
```

After a stub success the player is still here, so the session is resumed (`DataLoadStatus` back to `Loaded`, detail `Resumed`) and the next intent can be tested. A real `PrepareTeleport` save runs every time (`[DataService] … save Teleport ok seq=n`).

- Startup line: `[TravelService] mode=Stub (PlaceId 0) role=<Role> attempts=3`.
- Player attributes: `TravelState` (`Saving`, `Teleporting`, `Waiting`, `Returning`, `Done`, `Failed`, `Refused`, `Lost`, `Left`), `TravelLast` (`<intent> <state>: <detail>`), `TravelMessage` (last message key sent). Each change also prints `[TravelService] <name> (<userId>) <intent> <state>: <detail>`.
- Switches on `ServerScriptService` (server command bar, `game.ServerScriptService:SetAttribute(name, value)`):
  - `TravelStudioTrigger` (string): `Portal`, `WorldGate`, `MatchStart`, `Replay`, `ToLobby` or `LobbyButton`. Applies to the first player; `MatchStart`/`Replay` to all players. Resets itself to `""`. `LobbyButton` goes through the same path as the remote.
  - `TravelFailTeleport` (bool or number): `true` makes every stub teleport fail; a number `n` makes the next `n` fail and counts down.
  - `TravelStudioFriendJobId` (string), `TravelStudioFriendWorld` (number, default 1), `TravelStudioFriendServerFull` (bool): a fake online friend (UserId −999) on that server, written into the fake PresenceStore, so the real friend-preference code runs.
  - `DataFailSave`, `DataFailLoad`, `DataSimulateRejoin` from ADR 0006 force save and load failures.
- The saved zone can be set for the portal test with `require(game.ServerScriptService.Server.Services.DataService).GetProfile(game.Players:GetPlayers()[1]).sim.lastZone = 4`.

**Steps per Place** (`rojo build places/<place>.project.json -o build/test.rbxl`, open, Play; for group intents use a local server with 2 players):

| Place | Step | Expected |
|---|---|---|
| all | start | `mode=Stub (PlaceId 0) role=<Role>`; server count line as in Consequences; no errors |
| Lobby | trigger `Portal` | `to=Simulator world=1 zone=<sim.lastZone> placeId=0 server=Public … -> ok`; `TravelState=Done` |
| Lobby | `TravelStudioFriendJobId="friend-job"`, trigger `Portal` | `server=Friend(jobId=friend-job, friend=-999)`; with `TravelStudioFriendServerFull=true` or `TravelStudioFriendWorld=2`: `server=Public` |
| Lobby | trigger `MatchStart` (2 players) | `STUB ReserveServer placeId=0 -> studio-reserved-1`, then a line per player `to=Arena … server=Reserved(new, code=studio-reserved-1) players=Player1(-1),Player2(-2)` |
| Lobby | trigger `WorldGate`, `Replay`, `ToLobby`, `LobbyButton` | `<intent> for <name> refused: <intent> is not valid from Lobby`, `TravelState=Refused`, no STUB line |
| Lobby | `TravelFailTeleport=1`, trigger `Portal` | `attempt=1/3 -> simulated failure`, on screen "Teleport fehlgeschlagen. Neuer Versuch …", then `attempt=2/3 -> ok` |
| Lobby | `TravelFailTeleport=true`, trigger `Portal` | three simulated failures, final "Teleport fehlgeschlagen, du bleibst hier.", `TravelState=Failed`, `DataLoadStatus=Loaded`; set back to `false` |
| Lobby | `DataFailSave=true`, trigger `Portal` | no STUB line; after about 15 s "Speichern hat nicht geklappt. Neuer Versuch …", after about 35 s "Speichern fehlgeschlagen, du bleibst hier."; `TravelLast="Portal Failed: SaveFailed"`, `DataLoadStatus=Loaded`; set back to `false` |
| Lobby | `DataFailLoad=true`, `DataSimulateRejoin=<UserId>` | the player stays (`DataLoadStatus=Failed`), no `LoadFailReturn`; set back |
| World 1 | trigger `WorldGate` | `to=Simulator world=2 zone=11 placeId=0 server=Public … -> ok` |
| World 1 | trigger `LobbyButton`, and from the client command bar `require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers.TravelController).RequestLobby()` | `intent=LobbyButton from=Simulator to=Lobby … server=Public` both times |
| World 1 | `TravelFailTeleport=true`, then `RequestLobby()` twice quickly | second: `LobbyButton for <name> refused: already travelling (LobbyButton)` |
| World 1 | trigger `Portal`, `MatchStart`, `Replay`, `ToLobby` | refused, not valid from Simulator |
| World 1 | `DataFailLoad=true`, `DataSimulateRejoin=<UserId>` | two `status=Failed` lines (about 60 s: two loads of about 15 s each, 30 s apart), "Deine Daten laden gerade nicht. Zurück zur Lobby …", 5 s later `STUB teleport intent=LoadFailReturn from=Simulator to=Lobby … -> ok`; no DataService save line in between. `DataFailLoad=false` then loads at the next retry |
| World 1 | `DataFailSave=true` / `TravelFailTeleport` with `LobbyButton` | as in the Lobby |
| Arena | trigger `ToLobby` | `to=Lobby placeId=0 server=Public … -> ok` |
| Arena | trigger `Replay` (2 players) | `to=Arena … server=Reserved(new, code=studio-reserved-1)` per player |
| Arena | trigger `Portal`, `WorldGate`, `MatchStart`, `LobbyButton` | refused, not valid from Arena |
| Arena | `DataFailLoad=true`, `DataSimulateRejoin=<UserId>` | `LoadFailReturn … to=Lobby` as in World 1 |

## Consequences

- Server start counts are unchanged (`TravelService` added, `NetExampleService` removed; `PresenceStore` has no `Start`): 6 in Lobby, 8 in World 1, 5 in Arena. Client counts grow by one (`TravelController`): 3 in Lobby, 7 in World 1, 2 in Arena.
- Real teleports, the friend's server, full-server overflow, `ReserveServer`, private servers and MemoryStore quotas can only be verified on the human-published test version (concept 4.4). Before that, humans fill `Config.Places` and set the Simulator `MaxPlayers`.
- A save failure costs the player about 35 s of waiting before the final message (two `PrepareTeleport` calls, each with DataService's own retries). Tunable in `Config.Travel` and `Config.Data`.
- A teleport that times out but still completes later is safe: the lock was taken back, and the player's leave releases it, so the destination waits for the release (ADR 0006).
- `ReserveServer` failing is one failed travel (message, player stays); it is not retried within the travel.
- No save-format change: TravelService writes no profile field. `lastMode` stays with matchmaking.
- MemoryStore key names in `Config.Travel` are a cross-server format, but short-lived; renaming one loses only current presence and private mappings.
- Callers still to come: #37 (portal → `ToSimulator`, plus portal counts in PresenceStore), #105 (`ToNextWorld` after its open rule), 7.14 (`ToArena` with its reserved code and match record), 7.15/7.21 (`Replay`, `ToLobby`), #90 (button → `TravelController.RequestLobby`), #91 (popup).

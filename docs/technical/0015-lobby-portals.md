# 0015: Lobby portals, player counts, first-join arrow, group chest, news board and VIP corner

**Status:** Accepted with merge of PR #NN.

Implements `7.1-lobby-portals` (#37, Vertical Slice scope) on top of the map contract ([ADR 0009](0009-map-contract.md) "Lobby (7.1)" and "StreamingEnabled"), TravelService and PresenceStore ([ADR 0011](0011-travel-service.md)), DataService ([ADR 0006](0006-player-data.md), `IsPortalLocked` from #26), CurrencyService ([ADR 0007](0007-economy-config.md)) and the HUD scaffold ([ADR 0008](0008-hud-and-windows.md): prompts, pop-ups).

## Context

Concept 7.1 fixes: Singleplayer portal left, Multiplayer right, both visible from the spawn; walking into the Singleplayer portal starts a 3 s countdown that walking out cancels, then a teleport to the last world and zone (5.6); a board with the player count above each portal; a ground arrow and a pulsing rim at the Singleplayer portal for new players (decision 14.10., 10.1); a group chest that gives members of the Materiavis group 500 Coins and 100 Snow Coins (plus an egg and a hat) once; a news board with the last update and a countdown to the next; a VIP corner for VIP pass owners. Owner decisions 2026-11-09/10: in the Vertical Slice the Multiplayer portal is visible but closed (its mode window is #91), and the portal prompts use the #90 prompt component. Concept 6.5: while the profile is not loaded both portals stay locked, checked on the server.

The Lobby areas (`world/lobby/{Village,Plaza}.rbxmx`) are human work and not built. The Materiavis group id and the VIP pass id are not known yet. Egg 1 (#41) and the fight cosmetics (Launch) do not exist.

## Decision

**Layout.** Lobby-only code in `src/places/lobby/`; nothing runs in the other Places except the PresenceStore extension.

| Module | Kind | Role |
|---|---|---|
| `server/LobbyMap/` | Roblox (no `Start`) | Binds tagged instances below `Workspace.Map` per ADR 0009 (warn once `[MapContract] …, ignored`, never throw), box test, character root. Children: `MapRules` (pure: Station rule, `PortalMode`, BasePart, SpawnLocation, count warnings), `Box` (pure: inside, push out through a side wall), `AnswerCache` (pure: yes kept, no re-asked after a time, failure never kept). |
| `server/PortalService/` | service | Portals: entry check, countdown, travel, player counts, first-join arrow flag, Workspace positions. Children: `PortalCore` (pure state machine), `PlayerCounts` (refresh loop), `FirstJoinArrow` (pure flag rule). |
| `server/GroupChestService/` | service | Group chest prompt, membership, grant, save. Child: `ChestCore` (pure rule). |
| `server/NewsBoardService/` | service | Checks `NewsBoard` parts, publishes the next update time. |
| `server/VipCornerService/` | service | Keeps non-VIP characters out of `VipCorner` volumes. |
| `server/LobbyStudioService/` | service | Studio-only test layout and reset (below); does nothing on a live server. Child: `TestGeometry`. |
| `client/PortalController/` | controller | Boards above the portals, countdown ring and status line. Child: `PortalText` (pure). |
| `client/GuideArrowController/` | controller | First-join ground arrow and portal rim. Children: `GuideArrow` (reusable visuals for #42), `ArrowPath` (pure chevron positions). |
| `client/NewsBoardController/` | controller | News text on the board's `Front` face. Child: `NewsText` (pure). |
| `src/shared/LobbyAttributes.luau` | data | Attribute names shared by server and client. |
| `server/Services/PresenceStore` | extended | Per-mode player counts (below). |

`LobbySkeletonService` is removed. Numbers are in `Config.Lobby` (countdown, refresh, check intervals, VIP push-out, news, display, test layout), `Config.Economy` (`GroupChestCoins`, `GroupChestSnowCoins`, new `GroupId = 0`), `Config.Monetization.Gamepasses.Vip.AssetId` (0 placeholder), `Config.Travel` (mode count keys), names in `Config.Map` (Lobby tags, `PortalModeAttribute`, `PortalModes`, `PlayerCountAttribute`, `PlayerCountAtAttribute`), texts, pop-up keys and the `GroupChest` prompt preset in `Config.Ui` (additive).

**Portals (server-authoritative, no remote).** Every `Config.Lobby.PortalCheckInterval` (0.1 s) `PortalService` takes each living character's `HumanoidRootPart` position as the server sees it and tests it against every bound portal's `PrimaryPart` box. `PortalCore` turns that, `DataService.IsPortalLocked(player)` and `TravelService.IsTraveling(player)` into a state per player:

| State | When | Effect |
|---|---|---|
| `Idle` | outside every portal | — |
| `Countdown` | inside an open portal (Singleplayer), loaded, not travelling | ends `PortalCountdown` (3 s) after entry; leaving → `Idle` (event `Cancelled`); entering again starts a full new countdown |
| `Travelling` | the countdown reached 0 | `TravelService.ToSimulator(player)` (world and zone from the profile inside TravelService) |
| `WaitExit` | the travel ended (any outcome) and the character is still inside | nothing until the character leaves; so a Studio stub success or a failed teleport never loops |
| `Closed` | inside a mode in `Config.Lobby.ClosedPortalModes` (Vertical Slice: Multiplayer) | no countdown, no travel; the client shows "Coming soon" |
| `Locked` | inside an open portal while the profile is not loaded (6.5) | no countdown; a running countdown is cancelled (`CancelledLocked`); loading while inside starts the countdown |
| `Busy` | inside an open portal while another travel runs | no countdown |

There is no client→server remote for portals: the client cannot ask for a travel, so there is nothing to validate or rate-limit beyond the server's own check. "A teleport request of the client is refused while locked" (AC7) is the walk-in being refused (`Locked`); TravelCore also refuses `NotLoaded` on its own. Each state change writes the player attributes `PortalState`, `PortalCurrent` and `PortalCountdownEnds` (`Workspace:GetServerTimeNow()` of the end) on every server; the client draws the ring from them. The portal "prompt" is this walk-in countdown (concept 7.1: walking in starts it); a ProximityPrompt would contradict walking in, so the #90 prompt component is used for the group chest.

**Player counts.** `PresenceStore` gets one MemoryStore entry per portal mode: `mode_<PortalMode>` = `{ [jobId] = { c = players, t = Unix time } }`, written with `UpdateAsync` (stale servers older than `PresenceTtl` are dropped on every write, at most `Config.Travel.ModeMaxServers` = 400 servers per entry because a value is limited to 32 KB). Every public Simulator server's presence refresh (`PresenceStore.PublishServer`, every 30 s, ADR 0011) also writes its count into `mode_Singleplayer` (`Config.Travel.SimulatorMode`); `RemoveServer` takes it out. `PresenceStore.GetModeCount(mode)` sums the fresh servers (nil on a failed read). In the Lobby, `PlayerCounts` reads every mode every `Config.Lobby.PortalPlayerCountRefresh` (30 s, start to start) and writes `PlayerCount` and `PlayerCountAt` (Unix time of the last successful read, the diagnostic) on every bound portal Model; a failed read keeps both. Multiplayer: no server publishes yet, so it shows 0; matchmaking (7.14) calls `PresenceStore.SetModeCount("Multiplayer", jobId, n)` from the Arena. Private and reserved servers publish no presence (ADR 0011), so their players are not counted. The label (`BillboardGui` at `LabelAnchor`, else above `PrimaryPart`) is drawn by the client and refreshed on every attribute change.

**First-join arrow (7.1, 10.1).** The flag is the schema v1 field `tutorial.seenSingleArrow`. The server writes `LobbyShowSingleArrow` = loaded and not seen. The flag is set when the portal travel starts, before TravelService's save: a real teleport releases the session in that save, so a flag set after the teleport could never be stored. If the travel does not happen (`Refused`, `SaveFailed`, `TeleportFailed`) the old value is put back and the arrow shows again; the next save stores it. In Studio the stub "succeeds", so the flag is set and stored by the Teleport save and stays set after `DataSimulateRejoin`. The client draws pulsing chevrons from `Workspace.LobbySpawnPosition` to `Workspace.LobbyPortalPositionSingleplayer` (both written by the server when the spawn and the first portal of each mode bind, ADR 0009 "StreamingEnabled"; `LobbyPortalPositionMultiplayer` too, for #42) and a pulsing `Highlight` on the Singleplayer portal while it is streamed in. `GuideArrow` and `ArrowPath` take any start and target, so #42 adds the Multiplayer arrow (`seenMultiArrow`) and the animated hand without new drawing code.

**Group chest.** Each `GroupChest` station gets a prompt `Prompts.create("GroupChest", PrimaryPart, { tag = "GroupChestPrompt" })` ("Open" / "Group chest"). `ProximityPrompt.Triggered` is handled by `ChestCore.open` in this order: `Busy` (a check for this player is running: a double tap is one open), `Cooldown` (`GroupChestCooldown`, 1 s), `TooFar` (server distance from the root to `PrimaryPart` above the preset's `MaxActivationDistance` + `GroupChestReachSlack`), `NotReady` (no loaded profile), `AlreadyOpened`, then membership (`NotMember`, `NoGroup` when `Config.Economy.GroupId` is 0, `TryLater` when the web call failed), and after the yield the profile and the flag again. Then, with no yield in between, `groupChestClaimed = true`, `CurrencyService.AddCoins(500)`, `AddSnowCoins(100)`, then `DataService.SaveNow(player, "GroupChest")`. The flag and both balances are in one profile, so every save stores all three or none: a failed save keeps them on the server for the next autosave or the leave save, a rejoin onto the same server resumes them, a crash before any save loses all three together (the player can open once again), and nobody is ever paid twice. Membership is `Player:IsInGroupAsync(GroupId)` (fallback `IsInGroup`) in a pcall, cached by `AnswerCache` (member kept, non-member asked again after `GroupMembershipRecheck` = 10 s, so joining the group mid-session works). Pop-ups: "+500 Coins  +100 Snow Coins", "Already opened", "Join the Materiavis group", "Opens soon", "Try again in a moment", "Still loading…". The egg (Egg 1, #41) and the hat (fight cosmetics) are not granted in the slice (see "Open points").

**News board.** `NewsBoardService` writes `Workspace.LobbyNewsNextUpdateAt` from `Config.Lobby.News.NextUpdateAt` (Unix seconds, 0 = no date). `NewsBoardController` puts a `SurfaceGui` on the `Front` face of every `NewsBoard` part: "News", "Latest update: <Config.Lobby.News.LastUpdate>", "Next update in 2d 04:05:06" (server time, once per second) or "Next update: coming soon". Humans edit both values with each update.

**VIP corner.** Server-enforced: every `VipCheckInterval` (0.25 s) a non-VIP character whose root is inside a `VipCorner` volume is moved `VipPushOutMargin` (3 studs) out through the nearest side wall (`PivotTo`, height and facing kept). No collision group and no client check, so an exploited client cannot stay inside; doors and decor stay untagged and are not needed for the rule. Ownership is `MarketplaceService:UserOwnsGamePassAsync(userId, Config.Monetization.Gamepasses.Vip.AssetId)` in a pcall, asked in the background at join and then through `AnswerCache` (owner kept, non-owner asked again after `VipOwnershipRecheck` = 30 s); the loop never waits for it. With `AssetId = 0` nobody is VIP on a live server. A failed check counts as "not VIP" for that moment. The purchase itself and the other VIP perks are 9.2.

**Map binding.** As ADR 0009: stations (`Portal`, `GroupChest`) must be Models with `PrimaryPart` and `ModelStreamingMode = Atomic`; `Portal` also needs `PortalMode` `Singleplayer` or `Multiplayer`; `NewsBoard` and `VipCorner` must be BaseParts; `LobbySpawn` a SpawnLocation. Counts are warned once at start (`[MapContract] LobbySpawn: none in Workspace.Map`, `… Portal (Multiplayer): none …`). New names this ADR adds: `PlayerCountAt` on portal Models; Workspace attributes `LobbySpawnPosition`, `LobbyPortalPosition<Mode>`, `LobbyNewsNextUpdateAt`.

### Attributes

| Where | Name | Type | Servers | Meaning |
|---|---|---|---|---|
| Player | `PortalState` | string | all | state above |
| Player | `PortalCurrent` | string | all | the `PortalMode` the root is in, `""` outside |
| Player | `PortalCountdownEnds` | number | all | `Workspace:GetServerTimeNow()` at the end, `0` when not counting |
| Player | `LobbyShowSingleArrow` | bool | all | arrow shown |
| Player | `PortalLast` | string | Studio | last event, e.g. `Singleplayer Started`, `Singleplayer Cancelled`, `Singleplayer Travel`, `Multiplayer Closed`, `Singleplayer Locked`, `Singleplayer Finished` |
| Player | `PortalCountdownLeft` | number | Studio | seconds left (0.1 steps), `0` when not counting |
| Player | `PortalTravelResult` | string | Studio | outcome of the last portal travel (`Done`, `SaveFailed`, `TeleportFailed`, `Refused`, …) |
| Player | `GroupChestLast` | string | Studio | last chest outcome, e.g. `Opened saved=true`, `AlreadyOpened`, `NotMember` |
| Player | `GroupChestMember` | string | Studio | membership answer used (`Member`, `NotMember`, `NoGroup`, `Error`) |
| Player | `VipAccess` | bool | Studio | last access answer (written while inside the corner) |
| Player | `VipEjections` | number | Studio | times moved out |
| Portal Model | `PlayerCount`, `PlayerCountAt` | number | all | count and Unix time of the last refresh |
| Workspace | `LobbySpawnPosition`, `LobbyPortalPositionSingleplayer`, `LobbyPortalPositionMultiplayer` | Vector3 | all | positions for the arrow |
| Workspace | `LobbyNewsNextUpdateAt` | number | all | next update, Unix seconds |

### Studio playtest support (Studio at `game.PlaceId == 0` only; live servers skip all of it)

Startup lines: `[PortalService] started portals=<n> countdown=3s countRefresh=30s studioSwitches=true`, `[GroupChestService] started chests=<n> groupId=0 reward=500+100 studioSwitches=true`, `[NewsBoardService] started boards=<n> …`, `[VipCornerService] started volumes=<n> passId=0 studioSwitches=true`, `[LobbyStudioService] started switches=…`. Without the test layout the Lobby map is empty and the services warn `[MapContract] … none in Workspace.Map` once each; that is expected until the human-built Plaza exists. Every portal event prints `[PortalService] <name> (<userId>) <mode> <event>`, every travel `… <mode> travel <outcome>`, every chest try `[GroupChestService] <name> (<userId>) <outcome>`, every VIP push `[VipCornerService] <name> … moved out of …`.

Switches on `ServerScriptService` (server command bar, `game.ServerScriptService:SetAttribute(name, value)`):

| Switch | Type, default | Effect | Resets |
|---|---|---|---|
| `LobbyTestGeometry` | bool, `false` | `true` builds `Workspace.Map.LobbyTest` from `Config.Lobby.Test` and respawns every player on its `LobbySpawn`: a 200 × 200 `Grass` floor; `LobbySpawn` at the origin looking along −z; `PortalSingleplayer` (blue) 14 studs left and `PortalMultiplayer` (red) 14 studs right, both 45 studs ahead (walk-in volume 10 × 10 × 4, ring behind it, `LabelAnchor` above); `GroupChest` at (−30, 0, −15); `NewsBoard` at (30, 0, −15) facing the spawn; a VIP volume 16 × 10 × 16 at (45, 0, −45) with a "VIP" sign. `false` removes it. | stays |
| `LobbyTargetUserId` | number, `0` | the player `LobbyStudioReset` acts on; `0` = every player | stays |
| `LobbyStudioReset` | bool, `false` | `true` sets `groupChestClaimed = false` and `tutorial.seenSingleArrow = false` in the target's live profile (saved with the next save; balances unchanged, use `CurrencyResetCoins` / `CurrencyResetSnowCoins` of ADR 0007) and prints `LobbyStudioReset <name> (<id>): chest=true arrow=true` | itself to `false` |
| `LobbyStudioSimulatorPlayers` | number, `0` | a fake public Simulator server `studio-simulator` with that many players in the fake PresenceStore, kept fresh every second while > 0; the label shows it after the next refresh (≤ 30 s) through the real read path. `0` writes 0 once. | stays |
| `LobbyStudioGroup` | string, `""` | `"Member"`, `"NotMember"` or `"Error"` answers the group membership; `""` uses the real path (with `GroupId = 0`: `NoGroup`, "Opens soon") | stays |
| `LobbySimulateVip` | bool, `false` | `true`: every player counts as VIP owner | stays |
| `LobbyStudioNextUpdateIn` | number, `0` | `n > 0`: next update `n` seconds from now; `n < 0`: back to `Config.Lobby.News.NextUpdateAt` | itself to `0` |

Reused: `TravelFailTeleport`, `TravelStudioTrigger` (ADR 0011), `DataFailLoad`, `DataFailSave`, `DataSimulateRejoin`, `DataAutosaveNow` (ADR 0006), `CurrencyAddCoins`, `CurrencyReset*` (ADR 0007).

Read-only checks from the server command bar, for example: `local p = game.Players:GetPlayers()[1]; print(p:GetAttribute("PortalState"), p:GetAttribute("PortalCountdownLeft"), p:GetAttribute("PortalTravelResult"), p:GetAttribute("LobbyShowSingleArrow"))`, `print(workspace.Map.LobbyTest.PortalSingleplayer:GetAttribute("PlayerCount"), workspace.Map.LobbyTest.PortalSingleplayer:GetAttribute("PlayerCountAt"), os.time())`, `print(require(game.ServerScriptService.Server.Services.DataService).GetProfile(p).groupChestClaimed)`. On the client the arrow is the folder `workspace.LobbyGuideSingleplayer` (exists only while shown) and the rim the `Highlight` `LobbyGuideRim` under the portal.

**Steps** (`rojo build places/lobby.project.json -o build/test.rbxl`, open, Play, then `LobbyTestGeometry = true`):

| AC | Steps | Expected |
|---|---|---|
| AC1 | after the respawn, do not move the camera; screenshot | the blue Singleplayer portal with its board left of centre, the red Multiplayer portal with "Coming soon" right of centre, both whole in view |
| AC2 | walk (W) into the blue portal and stand | `PortalState=Countdown`, ring 3, 2, 1; about 3 s after entry `PortalLast="Singleplayer Travel"`, `[TravelService] STUB teleport intent=Portal from=Lobby to=Simulator world=1 zone=1 … -> ok`, `PortalTravelResult=Done`, `PortalState=WaitExit` until leaving |
| AC2 | walk in, walk out (S) after about 1 s | `PortalLast="Singleplayer Cancelled"`, `PortalCountdownLeft=0`, no STUB line |
| AC3 | walk into the red portal and stay 10 s | `PortalState=Closed`, "Coming soon", `PortalCountdownLeft=0`, no STUB line, `PortalTravelResult` unchanged |
| AC4 | read `PlayerCountAt` and `PlayerCount` of both portals, set `LobbyStudioSimulatorPlayers=7`, read again over 70 s | `PlayerCountAt` grows by 30 each refresh (never more than 30 apart); the blue board shows "7 playing" within 30 s; Multiplayer stays 0; `LobbyStudioSimulatorPlayers=0` → 0 within 30 s |
| AC5 | before any portal travel: screenshot | `LobbyShowSingleArrow=true`, yellow chevrons from the spawn to the blue portal, blue portal rim pulsing |
| AC5 | do the AC2 travel, then `DataSimulateRejoin=<UserId>` | after the travel `LobbyShowSingleArrow=false`, no chevrons, no rim; after the rejoin (`DataLoadStatus` back to `Loaded`) still `false`, the flag came from the store |
| AC6 | `LobbyStudioGroup="NotMember"`, open the chest (E) | "Join the Materiavis group", `GroupChestLast=NotMember`, Coins unchanged |
| AC6 | `LobbyStudioGroup="Member"`, press E twice quickly, then again | "+500 Coins  +100 Snow Coins" once, HUD Coins +500, Snow Coins +100, `GroupChestLast="Opened saved=true"`, then "Already opened"; balances unchanged |
| AC6 | `LobbyStudioGroup=""` (live default, GroupId 0), `LobbyStudioReset=true`, E | "Opens soon", `GroupChestLast=NoGroup` |
| AC7 | `DataFailLoad=true`, `DataSimulateRejoin=<UserId>`, walk into the blue portal | `DataLoadStatus=Failed`, `PortalState=Locked`, "Your progress is still loading…", no countdown, no STUB line; `DataFailLoad=false`: at the next load retry `PortalState=Countdown` while still inside, then the travel |
| AC12 | `LobbyStudioReset=true`, `LobbyStudioGroup="Member"`, `DataFailSave=true`, E (and E again while it saves); then `DataSimulateRejoin=<UserId>`; `DataFailSave=false`; `DataAutosaveNow=true`; `DataSimulateRejoin=<UserId>`; E | first E: "+500 …" at once and HUD +500 / +100, the second E shows nothing; after DataService's save retries `GroupChestLast="Opened saved=false"`; after the first rejoin `groupChestClaimed=true`, Coins kept (release failed, session resumed); after the autosave and the second rejoin still claimed with the same Coins; last E: "Already opened" |
| AC12 | `LobbyStudioReset=true` (arrow back), `DataFailSave=true`, walk into the blue portal | about 35 s: "Speichern fehlgeschlagen, du bleibst hier.", `PortalTravelResult=SaveFailed`, `LobbyShowSingleArrow=true` again; `DataFailSave=false`, walk out and in: travel `Done`, arrow gone |
| VIP | walk into the gold volume | moved out (`VipEjections` +1, console line); `LobbySimulateVip=true`: can walk in |
| News | `LobbyStudioNextUpdateIn=90`, look at the board | "Next update in 00:01:30" counting down; at 0 "Next update: coming soon" |

## Consequences

- Server start count in the Lobby grows from 8 to 12 (`PortalService`, `GroupChestService`, `NewsBoardService`, `VipCornerService`, `LobbyStudioService` replace `LobbySkeletonService`; `LobbyMap` has no `Start`). Client count in the Lobby grows from 6 to 9 (`PortalController`, `GuideArrowController`, `NewsBoardController`). World 1 (11 / 10) and Arena (7 / 5) are unchanged. (Counts on this branch include #90 and #28; ADR 0008 and 0011 each list their own.)
- AC1 is checked on the Studio test layout only. **The real Plaza (`world/lobby/Plaza.rbxmx`, human-built) needs the same check**: from the `LobbySpawn` default camera, without rotating, both portals in view, Singleplayer left. Builders tag it per ADR 0009 and the code binds it unchanged.
- Real group membership, the VIP pass, real teleports and MemoryStore counts across servers can only be verified on the human-published test version. Before that, humans fill `Config.Economy.GroupId`, `Config.Monetization.Gamepasses.Vip.AssetId` and `Config.Lobby.News`.
- `mode_<PortalMode>` is a new cross-server MemoryStore format (short-lived, TTL 60 s). One entry per mode written by every Simulator server every 30 s: at 400 servers that is about 13 writes per second on one key, within MemoryStore limits but the hottest key we have; above 400 servers the count is a lower bound. Sharding the entry is the fix if the game gets there.
- No save-format change: `groupChestClaimed` and `tutorial.seenSingleArrow` already exist in schema v1.
- The Lobby has no client→server remote; the declared remotes are unchanged.

## Open points

- The chest reward's egg (1 hatch from Egg 1, #41) and hat (fight cosmetics, Launch) are not granted. `groupChestClaimed` is one flag, so granting them later to players who already opened the chest needs either a new profile field (save format, owner decision) or a decision that early openers do not get them. In the Vertical Slice only Studio and test players open it.
- A failed group or pass check is shown as "Try again in a moment" (chest) and counts as "not VIP" (corner). An owner may prefer a different text.
- Players on private servers are not in the Singleplayer count (they publish no presence, ADR 0011).

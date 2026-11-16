# 0014: Zones 1–5, barriers, the zone teleport and the current zone

**Status:** Accepted with merge of PR #124.

Implements the Vertical Slice part of `7.6-zones-barriers` (#39, owner decisions 2026-11-10: zones 1–5 only, barrier at the end of zone 5 visible and closed, `Config.Zones.HighestOpenZone = 5`). Barriers 6–10 and the world gate are #105. Uses the map contract (ADR 0009), the Net layer (ADR 0005), DataService (ADR 0006), CurrencyService and `Formulas.Zones` (ADR 0007), the HUD scaffold (ADR 0008, #90: window stack, left-edge button, pop-ups, prompts) and BallService (ADR 0002).

## Context

Concept 7.6 fixes a maximum size, a scale and a barrier per zone, the barrier price `Ballwert(n) × B(n) × M(n)` (already `Formulas.Zones.barrierPrice`), the barrier UX ("Zone 6 · 3.7M" above it; walking in with enough coins opens "Zone 6 freischalten für 3.7M?" with Yes/No, with too few the missing amount), paid barriers open for good, the ball keeps its size into the next zone (decision 2026-10-08), and the zone teleport (T) lists only unlocked zones, teleports to the zone start and then waits 3 s. Concept 6.5 says paid barriers are saved at once, a double tap is one purchase, a crash never loses barriers, a player rejoins in the last visited zone and a fall goes back to the zone start with the ball's size kept. ADR 0009 says a barrier opens only if the next zone is in the map with one `ZoneStart` **and** at most the cap. Characters and balls are simulated by their owners, so "blocks some players, not others" needs a client part. The real zone maps (#29) are not built yet.

## Decision

**Layout.**

| Module | Kind | Role |
|---|---|---|
| `src/places/simulator/server/ZoneService/ZoneCore` | pure | Unlock purchase, barrier state (cap and map), zone teleport with wait, current and last zone, start zone, Studio reset, events. Config, formulas, map view, profile, coin spend and clock are injected. |
| `…/ZoneService/ZoneAreas` | pure | The shared zone-area resolver ADR 0009 asked for: which zones exist, which have exactly one `ZoneStart`, which zone a position is in (area boxes), part boxes. |
| `…/ZoneService/ZoneMap` | Roblox | Reads `Workspace.Map` into ZoneAreas records, binds `ZoneStart` and `Barrier` through CollectionService, warns once, writes the barrier attributes. Uses `UpgradeService/StationRules` for the ZoneIndex and Station rules (no copy). |
| `…/ZoneService/ZoneTestGeometry`, `ZoneStudio` | Roblox | Studio-only test zones and switches (below). |
| `…/ZoneService/init` | Roblox | Wires the core to DataService, CurrencyService, BallService, NetService and PopupService; the position check loop; spawn, teleport and return moves. |
| `src/places/simulator/client/ZoneController/` | client | `ZoneView` (pure: walk-in decision, labels, teleport rows), `Barriers` (labels, prompts, local passability, walking in), `UnlockWindow`, `TeleportWindow`, `ZoneRequests` (the only remote calls). |
| `src/shared/ZoneAttributes`, `PopupAmount` | pure | Attribute names and the `ZonesUnlocked` text form; the missing amount rounded up for the pop-up. |
| `src/shared/Config/Zones` (`HighestOpenZone`), `Config/Map` (tags `ZoneStart`, `Barrier`, barrier attributes and collision group, `ZoneAreas`, `ZoneTest`), `Config/Net` (`ZoneUnlock`, `ZoneTeleport`, `Zones.MaxZone`), `Config/Ui` (texts, pop-up keys, `Barrier` prompt preset), `Config/ZoneUi` (label and window look) | data | All numbers. |

**Save data.** No format change. ZoneService is the only writer of `sim.unlockedZones` (set with string keys; zone 1 is always unlocked, even if the key is missing), `sim.lastZone` (the zone the player last counted in) and `sim.highestZone` (highest unlocked zone). Malformed entries are ignored, never repaired.

**Barrier state (ADR 0009 "Closed without a code change per Place").** `ZoneCore.barrierState(n)` is the same for every player: closed with `WorldGate` (n is a world-gate zone or the last zone), `NoCap` (`HighestOpenZone` missing or not a whole number 1..`ZoneCount`), `Capped` (n + 1 > cap), `NotInMap` (no valid zone area n + 1 with exactly one `ZoneStart`), otherwise open. ZoneMap writes it on every bound barrier Model as `BarrierZone` (number, the zone it ends) and `BarrierCanOpen` (bool), on every server, at start and whenever the map changes. The client uses only barriers with these attributes. With the cap at 5, the barrier at the end of zone 5 stays closed even with a valid zone 6 in the map.

**Purchase (server).** The client sends one remote, `ZoneUnlock(zone)`: a whole number 1..`Config.Net.Zones.MaxZone` (= `ZoneCount`, checked by a spec), rate limit `Config.Net.RateLimits.ZoneUnlock` (burst 3, 1 per second). `ZoneCore.purchase` refuses in this order: `BadZone` (zone or zone − 1 not in this world), `NotLoaded` / `BadProfile`, `AlreadyUnlocked`, `NotAdjacent` (zone − 1 not unlocked), the barrier state of zone − 1 (`WorldGate`, `NoCap`, `Capped`, `NotInMap`), `NoBarrier` (no bound barrier in zone − 1), then `CurrencyService.SpendCoins(Formulas.Zones.barrierPrice(zone − 1))` (`Insufficient` …). Then, with no yield in between, `unlockedZones[tostring(zone)] = true` and `highestZone`. The player's position is not checked: a purchase from elsewhere only spends the player's own coins on the next zone in order, and a distance check would refuse legitimate taps from client-simulated characters at the face of the barrier.

**Saving (6.5).** After a successful unlock ZoneService calls `DataService.SaveNow(player, "Barrier")`. If it fails, the unlock and the spend stay on the server together (6.5 "Speichern schlägt fehl: der Stand bleibt auf dem Server") and the next autosave or the leave save stores both; nothing is rolled back and the barrier stays open. A double tap: the first request writes the unlock before it yields for the save, so the second is refused `AlreadyUnlocked`. A crash after the immediate save never loses the barrier.

**Barrier UX (client).** For each bound barrier:
- Label (BillboardGui `BarrierLabel` at `LabelAnchor`, else above `PrimaryPart`): `Zone N · <price>` with `NumberFormat.price` (rounds up), N = the zone it opens; `Zone N · Coming soon` while `BarrierCanOpen` is false; hidden once this player has unlocked zone N.
- Walking in: every 0.1 s the client checks whether its root is inside the barrier's box grown by 3 studs (`Config.ZoneUi`). On entry, `ZoneView.walkIn`: only if loaded, the barrier can open, its own zone is unlocked and the next is not. With `Coins ≥ price` the unlock window `ZoneUnlockWindow` opens ("Unlock Zone N for X?", Yes / No); with fewer coins the pop-up `BarrierNeedMore` ("Need {1} more"). A closed barrier (zone 5) does nothing.
- Prompt (`Prompts.create("Barrier", …)`, E / ButtonX, tag `BarrierPrompt`), only while this player can buy it: the same as walking in, so a player who chose No can reopen the window without walking away.
- Yes sends `ZoneUnlock(N)` and closes the window. The server answers with the pop-up `ZoneUnlocked` ("Zone 2 unlocked!"), or with `BarrierNeedMore` if the coins changed meanwhile.
- **Missing amount, rounded up.** Pop-up numbers use `NumberFormat.number`, which rounds down. `PopupAmount` rounds the missing amount up to the precision `NumberFormat.price` uses, so the pop-up text equals the price text ("Need 1.2K more" for 1,150), as the upgrade window (owner decision 2026-11-12). The client computes the price from the same formula and the server's `Coins`; the server sends the same pop-up on an `Insufficient` refusal.

**Passability.** Barrier parts stay solid on the server and for everybody by default. A client whose `ZonesUnlocked` lists zone N puts every BasePart of that barrier into the collision group `OpenBarrier`, locally. ZoneService registers it next to the ball groups with the rules `OpenBarrier` × `OwnCharacter` / `OwnBall` = false, × `Balls` / `OtherCharacters` / `Default` = true. Collision group changes do not replicate, so only this player's own character and ball pass; no part's `CanCollide` changes (the reviewed Simulator rule, `CollisionAssign.spec`). Streamed-in barriers get it again on `GetInstanceAddedSignal`.

**Current zone (server).** Every 0.25 s the server finds the zone area each character's root is in: the area's box (all its parts, 30 studs of vertical margin), the current zone winning where boxes overlap. Into an unlocked zone: `ZoneCore.enter` (sets `lastZone`) and `BallService.EnterZone`. Into a zone that is not unlocked (past a closed barrier by an exploit, or after a Studio reset): refused `Locked` and the character goes back to the start of its current zone, then 1 s grace. Outside every area (falling, the Placeholder) nothing changes.

**Ball size between zones.** `BallService.EnterZone(player, zone)` keeps the size in metres: `GrowthRules.carryFraction` recomputes the fraction in the new zone, and the ball grows on to the new maximum. Clamped to the new zone's range: a ball smaller than the next zone's start size starts at that start size (0.2 m → 0.25 m from zone 1 to 2), and a ball larger than a lower zone's maximum (zone teleport down, walking back) is capped at that maximum. The Studio switch `BallSetZone` keeps its old behaviour (`SetZone`, fraction kept) until the character crosses into another area.

**Spawn, rejoin, fall.** When the profile loads, ZoneService forgets the old session's zone, takes `ZoneCore.startZone` (the last visited zone if it is still unlocked and has a start here, else the highest unlocked zone with a start) and moves the character there. Every respawn goes to the start of the current zone, so falling off the map (Roblox kills the character) returns to the zone start; BallService keeps the ball's state. Moves wait up to 5 s for `RequestStreamAroundAsync`, then `PivotTo` the `ZoneStart` (3 studs above it, facing its look vector) and `BallService.PlaceAtCharacter` puts the ball in front. Without any zone area (today's Placeholder map) nothing is moved and Roblox's spawn stays.

**Zone teleport.** `ZoneTeleportWindow` (`MenuController.register` + `registerButton({ id = "ZoneTeleport", window = "ZoneTeleport" })`: T, D-pad up, the left-edge "Teleport" button) lists one button `Zone<N>` ("Zone 2 · Pine Forest", names from `Config.Zones.Names`) per zone in `ZonesUnlocked` of this world; "–" while not loaded. A tap sends `ZoneTeleport(N)` (same schema as `ZoneUnlock`, own rate limit). The server refuses `BadZone`, `NotLoaded`, `NotUnlocked`, `NoStart`, `NoCharacter` (pop-up `ZoneTeleportFailed`) and `Wait` within `Config.Zones.ZoneTeleportWait` (3 s) of the last teleport (pop-up `ZoneTeleportWait`, "Teleport ready in 2 s"); otherwise it counts the player in N and moves character and ball.

**Player attributes.**

| Attribute | Written | Meaning |
|---|---|---|
| `ZonesUnlocked` | every server, while the profile is loaded (nil otherwise) | `"1,2,3"`: unlocked zones, ascending. Client contract for the teleport list, labels, prompts and passability. |
| `ZoneCurrent`, `ZoneLastEvent`, `ZoneLastRefusal`, `ZoneRefusals`, `ZoneLastSave` | Studio at PlaceId 0 | Current zone; last unlock / teleport / enter / reset (e.g. `Unlock zone 2 Remote price=320`); last refusal (e.g. `Unlock zone 6 StudioSwitch refused: Capped`); refusal count; immediate save result (`zone 2 saved`, `zone 2 save failed: …`). |
| `ZoneOpenBarrierParts`, `ZoneLastWalkIn` | client-local on the LocalPlayer | Parts this client has in `OpenBarrier`; last walk-in or prompt decision (`zone 2 Window Walk`, `zone 3 NeedMore Prompt`, `zone 6 None Walk`). |

Barrier Models carry `BarrierZone` and `BarrierCanOpen` (every server) and `BarrierClosedReason` (Studio). Clients only read server attributes; a client write does not replicate.

**Shared resolver for other features.** `ZoneService.ZoneOfInstance(instance)`, `ZoneOfPosition(position)`, `HasZone(zone)`, `GetZone(player)`, `GetUnlocked(player)`, `IsUnlocked(player, zone)` and `Subscribe(fn)` (Unlock, Teleport, Enter, Reset, Refused events for #43). Finds (#40) and other zone-bound features use these instead of their own lookup.

**Studio playtest support (Studio at `game.PlaceId == 0` only; live servers skip all of it).**
- Startup line, always printed: `[ZoneService] started cap=5 zones=… starts=… barriers=… collisions=ok studioSwitches=true`. Every event prints `[ZoneService] <name> (<userId>) <text>`; bound barriers print `barrier bound <full name> zone=<n> canOpen=<bool> <reason>`.
- `ServerScriptService.ZoneMapState` (string): e.g. `zones=1,2,3,4,5,6 starts=1,2,3,4,5,6 barriers=1:open,2:open,3:open,4:open,5:closed(Capped),6:closed(NotInMap) cap=5`.
- Switches on `ServerScriptService`:

| Attribute | Type, idle | Effect | Reset |
|---|---|---|---|
| `ZoneTargetUserId` | number, `0` | Player the switches act on; `0` = every player. | stays |
| `ZoneTestGeometry` | bool, `false` | `true` builds `Workspace.Map.ZoneTest01` … `ZoneTest06` (Folders with `ZoneIndex` 1–6, each a 120 × 80 Snow floor along +X from x = 1100, z −40..40, top y = 0, beyond the Placeholder's +X edge; a `ZoneStart` Attachment 12 studs into the zone facing +X; a `Barrier` Model (Atomic, `PrimaryPart` `Gate`, 2 × 16 × 80, half transparent, `LabelAnchor`) at the zone's +X end), then moves the targets to the start of their zone. Refused with a log line if another area already uses ZoneIndex 1–6 (build it before other test areas, which then pick a free ZoneIndex). `false` removes them. | stays |
| `ZonePurchase` | number, `0` | Runs the unlock of that zone for the targets through the remote's path (without the Net guard): every refusal, the spend, the immediate save, the pop-ups. | itself to `0` |
| `ZoneTeleportTo` | number, `0` | Runs a zone teleport for the targets through the remote's path, including the 3 s wait. | itself to `0` |
| `ZoneResetUnlocks` | bool, `false` | Resets the targets to zone 1 only (`unlockedZones`, `highestZone`, `lastZone`), in memory; the next save stores it. The position check then returns a player standing in a higher zone to zone 1. | itself to `false` |

- With `CurrencyAddCoins` (ADR 0007), `DataFailSave`, `DataAutosaveNow`, `DataSimulateRejoin` (ADR 0006) and `BallSetSizeFraction` / `BallGrowthPaused` (ADR 0002) a playtest can buy, fail the immediate save, save again, rejoin and check the ball size across a barrier.

## Consequences

- World 1 starts one more server service (`ZoneService`, 12) and one more client controller (`ZoneController`, 11). Lobby and Arena are unchanged; their NetService creates `ZoneUnlock` and `ZoneTeleport` (shared declaration list) and drops calls as `NoHandler`.
- Real zone areas from #29 bind without code changes; a sixth area (#104) stays closed until #105 raises `HighestOpenZone`.
- The ball's zone now follows the character. `Config.Ball.DefaultZone` is only where a new ball starts before ZoneService moves it.
- A ball is capped at a lower zone's maximum when the player goes back (see "Decided by Dev Manager" in PR). If design wants the size kept above the maximum, the fraction model of BallService needs a value above 1.
- `CollisionAssign.spec` now also allows exactly two `FireServer(zone)` calls in `ZoneRequests`.
- `ZoneTestGeometry` and other features' test areas share the ZoneIndex space; the first one built wins and the others refuse or pick free values.
- `BallService/init.luau` grows from 420 to about 460 lines (two small zone entry points); splitting it is left to a BallService change.
- The zone teleport window and the unlock window live in their own ScreenGui `ZoneHud`; they use the ADR 0008 stack, layout and components, so they follow its ⅔ limit and clear zones.

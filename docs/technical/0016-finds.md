# 0016: Finds

**Status:** Accepted with merge of PR #127.

Implements `7.7-finds` (#40) from the `FindService` row of [ADR 0003](0003-snow-rush-intake.md): the Alps finds and the secret find at Launch. The collection book UI is #70 (`7.13-collection-book`). Uses the map contract (`FindPoint`, [ADR 0009](0009-map-contract.md)), ZoneService's shared zone resolver ([ADR 0014](0014-zones-barriers.md)), Net ([ADR 0005](0005-net-remotes.md)), DataService ([ADR 0006](0006-player-data.md)), `Rng` and `Formulas.Economy.findValue` ([ADR 0007](0007-economy-config.md)), the HUD pop-ups ([ADR 0008](0008-hud-and-windows.md)), the Magnet upgrade ([ADR 0010](0010-upgrades.md)) and `SellService.AddFindValue` ([ADR 0012](0012-selling.md)).

## Context

Concept 7.7: at fixed points in a zone a find appears every 20 seconds if none lies there. Finds are per player (🟦: everybody sees and collects their own). They stick in the ball and raise its value (2 / 5 / 15 / 50 / 200 % of a full ball of the current zone, ✅), very rare finds show a short pop-up, the rarity is always shown with colour and stars (8.5), and every find is in the collection from the pickup on, while its value counts only at the sale. Chances 60 / 25 / 10 / 4 / 1 %, with Legendary only in zones 6–10 of each world (zones 1–5 give that 1 % to Common). The secret find (Yeti Footprint) has 1 in 2,000 per spawned find in every world and gives a title and a ball effect. Concept 6.5: leaving while pushing a ball loses its size and its finds, but the finds stay in the collection. Owner decisions: find points come from the map contract (2026-11-10); finds visible in the ball until it is sold, checked with selling (2026-11-10, #38); Magnet is unlocked here and must act at once (2026-11-12, #36). Spielraum: models, placement of the points, the spawn effect. The real zone maps (#29) are not built yet.

## Decision

**Layout.**

| Module | Kind | Role |
|---|---|---|
| `src/places/simulator/server/FindService/FindCore` | pure | Points (slots), per-player spawn timers, the roll (incl. Studio forcing), pickup, value, collection and title writes, finds in the ball, events. Config, odds, picker, value formula, profile, unlocked check, ball value add, generator and clocks are injected. |
| `…/FindService/FindPoints` | Roblox | Binds `FindPoint` anchors below `Workspace.Map` through CollectionService; the zone comes from `ZoneService.ZoneOfInstance`. |
| `…/FindService/FindStudio` | Roblox | Studio switches, test points, diagnostics. |
| `…/FindService/init` | Roblox | Wires the core to the map, DataService, BallService, UpgradeService, SellService, ZoneService, PopupService and the `FindUpdate` remote. |
| `src/places/simulator/client/FindController/` | client | `FindView` (pure: accepted updates, places and sizes in the ball) and `init` (billboards, finds in the own ball, ball effect). |
| `src/shared/Config/Finds` | data | Odds, values, catalogue, secret reward, pop-up rarities, timing, look, test points, diagnostic names. |
| `Config/Map` (`Tags.FindPoint`), `Config/Net` (`FindUpdate` limit, `Finds` bounds), `Config/Ui` (pop-up texts), `Config/Upgrades` (`Locked` now empty) | data | Additive entries. |

**Points (ADR 0009).** `FindPoint` is an anchor: an Attachment (`WorldPosition`) or a BasePart (`Position`), any number per zone. Binding at start and on `GetInstanceAddedSignal`, unbinding on `GetInstanceRemovedSignal`. Outside `Workspace.Map`: ignored silently. Another instance kind, or not in a zone area with a valid `ZoneIndex`: `[MapContract] FindPoint <full name>: <problem>, ignored`, once per instance (the `StationRules.warning` text). The zone is resolved by `ZoneService.ZoneOfInstance` (no second resolver); zone and position are read once when the point binds and cached, as ADR 0009 says. Each bound point gets a slot number (counts up per server, never reused).

**Spawning (server, AC1, 7.7 🟦).** Per player and point there is at most one find. When a player's profile is `Loaded`, every point is empty "since now"; a point that has been empty for `Config.Finds.SpawnInterval` (20 s) gets a new find. After a pickup the same point is empty again, so its next find comes 20 s later. The server checks every `SpawnCheckInterval` (0.25 s), so a spawn is at most 0.25 s late. Every bound point spawns for every loaded player, also in zones the player has not unlocked (unreachable behind the barrier; the pickup refuses them, see below). Finds exist only at bound points. When a point is unbound its finds are removed; when the profile stops being loaded (`Released`, `Teleported`, `Lost`, a Studio rejoin) all spawned finds of that player are dropped.

**Roll (server, AC3, AC7).** `Rng.findOdds(zone)` is the table: zones 1–5 of each world 61 / 25 / 10 / 4 / 0, zones 6–10 60 / 25 / 10 / 4 / 1, each with the secret find's 0.05 % taken off in proportion (the same as rolling the secret first). One uniform roll from a generator used only for finds (`Rng.new()`) picks the rarity (`Rng.pick`). The find is `Config.Finds.ByWorld[world][rarity]` (World 1: Pine Cone, Chocolate Bar, Edelweiss, Rock Crystal, Golden Cowbell) or `SecretFind` (Yeti Footprint) in every world. A world without a catalogue entry spawns nothing and warns once (worlds 2–5 come with 7.6b–d).

**Pickup (server, AC2, AC5, AC6, AC9).** Every `PickupCheckInterval` (0.1 s), for each player: the server's view of the ball (`BallService.GetBallPart`: centre and radius) and the Magnet effect `UpgradeService.GetEffect(player, "magnet")` (4 studs at level 0 to 24 at level 100), read at every check, so a purchase acts at the next check. A spawned find is in reach when the gap between the ball's surface and the point is at most the Magnet radius. It is picked up only if the owner is at the ball (`BallService.IsHeld`, the 7.4 growth range) and its zone is unlocked (`ZoneService.IsUnlocked`); otherwise a `Refused` event (`NotHeld`, `Locked`) is emitted once per find. A pickup does, without a yield:

1. removes the spawned find (the point's 20 s start now),
2. adds `Formulas.Economy.findValue(zone of the point, rarity)` (share × `fullBallValue(zone)`, the zone the find lies in) to the current ball with `SellService.AddFindValue`; the secret find adds 0,
3. writes `sim.collection.finds[findId] = os.time()` if the id is not there yet (first time kept),
4. for the secret find: `sim.titles[Config.Finds.SecretTitle] = true` (`YetiTracker`),
5. appends the id to the ball's finds and tells the client.

The client sends nothing for any of this: no remote, no position, no size. An exploiting owner still simulates its own ball and character, so the most it can do is collect its own finds in unlocked zones, which play allows anyway, at most one per point per 20 s.

**Saving (AC5, 6.5).** No format change. FindService is the only writer of `sim.collection.finds` and `sim.titles` (source check). A find is in the live profile from the pickup on; it is stored with the next autosave (≤ 2 min) or the leave save, like coins: finds are not in the immediate-save list of 6.5 / ADR 0003. A failed save keeps it on the server and the next save stores it; a failed leave save keeps the lock and the autosave stores it (fake-store specs). A server crash loses at most the last autosave interval (6.5 "Serverabsturz"). The finds in the ball and their value are not saved: leaving loses them (SellService and FindService forget them on `PlayerRemoving`), the collection keeps them. Malformed collection or title tables are left alone, never repaired; the find still counts in the ball.

**Sale (AC4).** `SellService.Subscribe` delivers `Sale`: FindService empties that player's ball finds and sends `ClearBall`. Nothing else empties them (a respawn round, a zone change or a Studio rejoin keeps the ball and its finds, as SellService keeps their value).

**Pop-ups and secret reward.** On pickup of a find whose rarity is in `Config.Finds.PopupRarities` (Epic, Legendary, Secret) the server shows its `PopupKey` through `PopupService.show`: "★★★★ Epic: Rock Crystal!", "★★★★★ Legendary: Golden Cowbell!", "👑 Secret: Yeti Footprint!". A new title adds "New title: Yeti Tracker". The ball effect is derived from the titles (`Config.Finds.BallEffects`, `YetiTracker` → `YetiSparkles`), so it needs no own save field: every server writes the Player attribute `FindBallEffect` (client contract) on load and when the title is new, and clears it when the profile is no longer loaded.

**Client (`FindUpdate`, display only).** `FindUpdate` is declared in `Net/Remotes` as server → client only: action (`Spawn`, `Remove`, `Collect`, `ClearBall`, `Reset`, `Config.Net.Finds.Actions`), then an optional slot (whole 1..`MaxSlot`), find id (string ≤ `MaxIdLength`) and position (`Vector3`, |v| ≤ `MaxPositionMagnitude`), rate limit `Config.Net.RateLimits.FindUpdate`, no server handler (a client call is dropped as `NoHandler`). The server fires it only to the player the find belongs to. `FindController` checks every argument again (catalogue id, slot) and draws:
- a spawned find: an Attachment `Find_<slot>` in `Workspace.Terrain` `HeightAboveGround` above the point, with a BillboardGui `FindBillboard`: a disc in the rarity colour (`Rarity.color3`) with a white ring and the stars or the crown (`Rarity.get(id).symbol`) under it, `SizeStuds`, `MaxDistance` 150 studs. No part is created, so nothing local collides with a character or a ball (the Simulator never writes `CanCollide`, `CollisionAssign.spec`). Attributes `FindId`, `Rarity`, `Slot` on the billboard and `FindId`, `Point` (the server position) on the attachment.
- finds in the own ball (`Workspace.SnowBalls` child with `OwnerUserId` = LocalPlayer): up to `MaxInBall` (24) Attachments `FindInBall_<n>` inside the ball part on its surface (Fibonacci-sphere places, visited with a stride so the first finds go round the ball), sized `InBallShare` of the diameter within 0.6–3 studs and moved with every Size change, until `ClearBall`. All finds still count for the sale. Other players' finds in their balls are not drawn (ADR 0003 R2).
- the ball effect: built-in `Sparkles` (no asset) named `FindBallEffect` in the Secret colour on every ball whose owner has `FindBallEffect`.

Read-only client handles on the LocalPlayer: `FindClientVisible` (spawned finds drawn), `FindClientInBall` (finds drawn in the own ball).

**Upgrade.** `magnet` is removed from `Config.Upgrades.Locked`, which is now empty: the menu shows its price and buy button and the server accepts its purchase (owner decision 2026-11-12). The lock mechanism stays and is specced with a test-only table.

**Server API.** `FindService.GetBallFinds(player)` and `FindService.Subscribe(fn)` (`Spawn`, `Remove`, `Collect`, `ClearBall`, `Reset`, `Refused`, for analytics #43; listeners must not yield).

**Studio playtest support (Studio at `game.PlaceId == 0` only; live servers skip all of it).**
- Startup line, always printed: `[FindService] started points=<n> interval=20s studioSwitches=true`. Bound points print `[FindService] point bound <full name> zone=<n> slot=<s>`. Every event prints `[FindService] <name> (<userId>) <text>`, e.g. `spawn slot 4 zone 1 Edelweiss (Rare) roll=0.9123`, `pickup slot 4 zone 1 Edelweiss (Rare) value=12 first=true`, `refused slot 16 zone 6 GoldenCowbell: Locked`.
- `ServerScriptService.FindPointsState` (string): `points=18 zones=1:3,2:3,3:3,4:3,5:3,6:3`.
- Diagnostic Player attributes: `FindSpawnedCount`, `FindSpawnedList` (`slot:zone:findId,…`), `FindLastSpawn` (text), `FindLastSpawnSlot`, `FindLastSpawnClock` (server `os.clock()`), `FindLastRoll` (the roll, `-1` when the rarity was forced), `FindLastPickup` (text), `FindLastPickupSlot`, `FindLastPickupClock`, `FindLastPickupValue`, `FindLastPickupZone`, `FindLastRefusal`, `FindBallCount`, `FindBallList`, `FindCollection` (ids in `sim.collection.finds`, sorted), `FindCollectionCount`, `FindTitles`, `FindMagnetRadius` (live, written on change). `SellFindsValue` (ADR 0012) is the value in the ball. The respawn time of a point is `FindLastSpawnClock − FindLastPickupClock` when `FindLastSpawnSlot == FindLastPickupSlot`.
- Switches on `ServerScriptService`:

| Attribute | Type, idle | Effect | Reset |
|---|---|---|---|
| `FindTargetUserId` | number, `0` | Player the switches act on; `0` = every player. | stays |
| `FindTestPoints` | bool, `false` | `true` puts three `FindPoint` Attachments `FindTestPoint1..3` into the floor of each `Workspace.Map.ZoneTest01..06` (ZoneTestGeometry, ADR 0014: set `ZoneTestGeometry = true` first), at x = 36 / 60 / 84 studs from the zone's start edge, z = −16 / 14 / −4 from its centre line, on the floor top. They bind through the normal map path. Without test zones it builds nothing and says so. `false` removes them. The points use the test zones' own ZoneIndex 1–6, so they cannot clash with other test areas. | stays |
| `FindForceRarity` | string, `""` | Every spawn of the targets gets this rarity (`Common` … `Legendary`, `Secret`). A rarity the zone's table does not have (Legendary in zones 1–5) is refused and the normal roll decides (the log says `forced Legendary refused in this zone`). | stays |
| `FindForceRoll` | number, `-1` | Every spawn of the targets uses this roll in [0, 1) instead of the generator (`-1` = off). `0.995` gives Epic in zones 1–5 and Legendary in zones 6–10; `0.9999` gives the secret find. `FindForceRarity` wins when both are set and allowed. | stays |
| `FindRespawnNow` | bool, `false` | Removes the targets' spawned finds and spawns a new one at every point now (with the forcing). The normal 20 s rule goes on from there. | itself to `false` |

- Reused switches: `ZoneTestGeometry`, `ZonePurchase`, `ZoneTeleportTo` (ADR 0014) for zones; `SellScaleTestGeometry` (ADR 0012; with the test zones use a free zone such as `7`) to sell; `UpgradeSetLevel`, `UpgradePurchase` (ADR 0010) and `CurrencyAddCoins` (ADR 0007) for Magnet; `BallSetSizeFraction`, `BallGrowthPaused` (ADR 0002) for exact sizes; `DataFailSave`, `DataAutosaveNow`, `DataSimulateRejoin` (ADR 0006) for the save cases.

## Consequences

- World 1 starts one more server service (`FindService`) and one more client controller (`FindController`). With selling (ADR 0012) and zones (ADR 0014) both merged, World 1 starts 14 server services and 13 client controllers (each of those ADRs counted only its own addition: 12 and 11). Lobby and Arena are unchanged; their NetService creates `FindUpdate` (shared declaration list) and drops client calls as `NoHandler`.
- Real find points come with the zone builds (#29), tagged `FindPoint` inside each `ZoneNN` area; no code change. 6.2 asks 8–12 per zone (checked in the #29 review, not by code).
- The find catalogues of worlds 2–5 are added to `Config.Finds.Items` / `ByWorld` with their worlds. Item ids are save-format keys and must never be renamed.
- The collection book (#70) reads `sim.collection.finds`; the odds it must show are `Rng.findOdds(zone)`.
- Placeholders only: models, the spawn effect and the rainbow look of the Secret tier are Spielraum and left to art. The ball effect is always on while the title is owned; choosing or hiding effects is not designed yet.
- A crash can lose the finds of the last autosave interval (6.5 allows 2 min). Finds are not in the immediate-save list.

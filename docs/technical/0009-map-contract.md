# 0009: Map contract, tags and attributes for World 1 zones and the Lobby

**Status:** Accepted with merge of PR #106.

Implements #101. Extends the map section of [ADR 0003](0003-snow-rush-intake.md) ("Gameplay code binds to the maps only through CollectionService tags and named anchor attachments", D3, StreamingEnabled) and keeps the names of [ADR 0002](0002-snowball-push-ownership-size-cap.md). Builders (#29, #104, #37) and the station bindings (#36, #38, #39, #40, #41, #105) follow it.

## Context

ADR 0003 names only the surface tags. ADR 0002 added `Obstacle`, `KnockOverSize` and `ScaleAnchor`. The Vertical Slice maps (zones 1–5, Lobby) are about to be built, and builders need one written list of what to tag and which attributes to set before gameplay code binds to it. Concept v5 6.2, 7.1, 7.6, 7.7, 7.8 and 7.9 say what each zone and the Lobby contain; the technical names are Development's call (#101 Spielraum).

Constraints: StreamingEnabled is on in every Place, so a client may not have a part. The server is authoritative, so every binding that changes state is server-side. Game design values (prices, odds, zone names, rewards) live in `src/shared/Config/*` and `Formulas/*` and must not be copied into the map, or the map and Config could disagree. Owner decisions 2026-11-10: in the Vertical Slice the barrier at the end of zone 5, the Multiplayer portal and (at Launch) the world gate at the end of zone 10 are visible but closed.

## Decision

### General rules

| Rule | Meaning |
|---|---|
| Scope | Code binds only to tagged instances that are descendants of `Workspace.Map`. Tagged templates elsewhere (for example `ServerStorage.Kit`) are ignored without a warning. |
| Names | Tags and attributes are PascalCase. New names do not reuse an existing name with another meaning. |
| Anchor | "Anchor" below means an `Attachment` (position `WorldPosition`, orientation `WorldCFrame`) or a `BasePart` (`Position`, `CFrame`), as `ScaleAnchor` already accepts. Prefer an Attachment: it costs no physics. |
| Station | "Station" below means a `Model` with the tag on the Model itself, `PrimaryPart` set (code puts its prompt there and uses it as the station position) and `ModelStreamingMode = Atomic`. An optional `Attachment` named `LabelAnchor` anywhere inside it marks where code puts the station's label (price, odds, player count, sign). Without one the label goes above `PrimaryPart`. |
| Missing or invalid | The server checks at start and on every `GetInstanceAddedSignal`. A problem warns **once per instance** (`[MapContract] <tag> <full name>: <problem>, ignored`) and the instance is not bound. Nothing throws, so one bad part never stops a Place. The client never validates: it shows only what the server bound. |
| No design values | No price, odds, reward, zone name or pet appears as an attribute. Code reads them from `Config/*` and `Formulas/*` using the zone number. |

### Zone number (Simulator)

| Item | Rule |
|---|---|
| Where | Number attribute **`ZoneIndex`** on the **zone area root**, the direct child of `Workspace.Map` (`Workspace.Map.ZoneNN`, from `world/world1/ZoneNN.rbxmx`). Parts never carry it. |
| Value | Whole number, global zone number (1–50), and inside this Place's world: `Formulas.Zones.worldOf(ZoneIndex) == PlaceInfo.WorldIndex`. |
| Resolve | An instance's zone is the `ZoneIndex` of the ancestor that is a direct child of `Workspace.Map`. One rule, no inheritance chain and no per-part override. Code resolves it once per instance when binding and caches it. |
| Missing or invalid | Area without `ZoneIndex` (for example today's `Placeholder`): it has no zone. Its zone-bound entries (marked "zone" below) are ignored with the warning. Surfaces, obstacles and `ScaleAnchor` do not need a zone and keep working. Invalid value: warn once and treat the area as having no zone. Two areas with the same `ZoneIndex`: warn once and treat both as having no zone. |
| Ignored | A `ZoneIndex` on any deeper instance is ignored with a warning, so a builder cannot think it overrides the area. |
| Name | The area name `ZoneNN` is a convention for people; code reads only the attribute. `ZoneIndex` matches `WorldIndex` and does not collide with the ball part's runtime attribute `Zone` (ADR 0002). |
| Streaming | The area root is a `Folder` or a `Model` with `ModelStreamingMode` `Default` or `Nonatomic`, never `Atomic` or `Persistent`. Then the root and its attribute replicate at join and a streamed-in part on the client can resolve its zone. |

### Existing names (unchanged)

| Tag / attribute | Instance kind | Attributes | Missing or invalid | Source |
|---|---|---|---|---|
| `Snow`, `DeepSnow`, `Ice`, `Grass` | BasePart (ground, mesh or flat non-colliding patch) | — | Untagged ground gives no growth. Several tags: first in `Config.Ball.SurfacePriority` | ADR 0003 D3, `Config.Ball.Surfaces` |
| `Obstacle` | BasePart (box-shaped contact test) | `KnockOverSize`: number, studs, optional | Missing, non-finite or ≤ 0: never knocked over | ADR 0002, `Config.Ball.ObstacleTag`, `KnockOverSizeAttribute` |
| `ScaleAnchor` | Anchor | — | Not found: no MAX arrow target (`BallScaleAnchor` stays unset) | ADR 0002, `Config.Ball.ScaleAnchorTag` |

### Simulator (World 1 zones)

| Entry (concept) | Tag | Instance kind | Attributes | Count per zone | Missing or invalid |
|---|---|---|---|---|---|
| Zone start: spawn and zone-teleport target (7.6) | `ZoneStart` (zone) | Anchor. The character is placed on it, facing its `LookVector` | — | exactly 1 | 0 or more than 1: warn once, the zone has no start. Zone teleport into it is refused with the normal failure message, and a barrier into it stays closed. |
| Find point (7.7) | `FindPoint` (zone) | Anchor at the spot the find lies on | — | any (6.2 asks 8–12; checked in the #29 review, not by code) | Outside a zone: ignored with the warning |
| Egg station (7.9) | `EggStation` (zone) | Station | — . The egg is the `k` with `Formulas.Pets.eggZone(k) == ZoneIndex` (Config `EggZones`: egg 1 in zone 1, egg 2 in zone 5) | 0 or 1 | In a zone without an egg: warn, ignored. More than 1: warn, all work. Whether that egg can be bought yet (egg 2 with #103) is decided in code, not by the map. |
| Upgrade stand (7.8) | `UpgradeStand` (zone) | Station; opens the same menu as U | — | any (6.2: one at the zone end) | Outside a zone: ignored with the warning |
| Scale (7.5, 7.6) | `ScaleAnchor` (unchanged) | Anchor | — | 1 (7.6 Fix) | See "Existing names" |
| Scale sell area (7.5) | `ScalePlate` (zone) | BasePart: the volume a ball must touch to sell | — | at least 1 | None in a zone: that zone has no selling, warn once per zone. #38 confirms or replaces this entry. |
| Barrier (7.6) | `Barrier` (zone) | Station. Its blocking parts are inside the Model | — . It opens `ZoneIndex + 1`; the price is `Formulas.Zones.barrierPrice(ZoneIndex)` | 1, except the last zone of a world (`Formulas.Zones.isWorldGate`) and zone 50 | In a world-gate zone or zone 50: warn, ignored. 0: warn, the next zone is unreachable. More than 1: warn, all work. |
| World gate (7.6) | `WorldGate` (zone) | Station | — . Target world is `PlaceInfo.WorldIndex + 1`, price as the barrier of its zone | 1, only where `isWorldGate(ZoneIndex)` | Elsewhere: warn, ignored |

**Closed without a code change per Place**

| What | Closed while | Opens when | Decided by |
|---|---|---|---|
| Barrier at the end of zone n | always, unless both hold: (a) this Place has a valid zone area with `ZoneIndex == n + 1` and exactly one `ZoneStart`, and (b) `n + 1 ≤ Config.Zones.HighestOpenZone` (number, Vertical Slice 5). The cap does not exist yet. If it is missing or invalid (not a whole number from 1 to `ZoneCount`), every barrier stays closed and only zones the player already unlocked stay reachable | the zone area is in the map **and** a reviewed PR raises the cap to at least n + 1 | #39 adds the cap with value 5 (zones 1–5), #105 raises it (10 at Launch) |
| World gate at the end of zone 10 | `Config.Places.Worlds[WorldIndex + 1]` is missing or `0` (concept: "solange die nächste Welt noch nicht erschienen ist") | humans fill the World 2 PlaceId at publish (#65) | #105; sign text is #105's (7.6 Spielraum) |
| Multiplayer portal | no countdown, no teleport in the Vertical Slice | #91 adds the mode window | #37 builds it closed, #91 opens it in code. No map attribute, because opening needs new code anyway. |

A closed station keeps its Model and collision, shows its label and creates no purchase prompt or window. The zone teleport lists only zones the player has unlocked, so the cap matters only for barriers.

### Lobby (7.1)

| Entry | Tag | Instance kind | Attributes | Count | Missing or invalid |
|---|---|---|---|---|---|
| Spawn (village square, facing the portals) | `LobbySpawn` | `SpawnLocation` (Roblox spawns on it; the tag lets code find it, e.g. the first-join arrow #42) | — | exactly 1 | 0: warn, Roblox default spawn. More than 1: warn; Roblox picks among them. |
| Portal | `Portal` | Station. `PrimaryPart` is the walk-in volume (non-colliding) | `PortalMode`: string, required, `"Singleplayer"` or `"Multiplayer"` | 1 per mode | Missing or other value: warn, ignored (no countdown). Mode missing: warn, that mode has no portal. More than 1 of a mode: warn, all work. |
| Player-count board above each portal | none (part of the portal) | The portal's `LabelAnchor` | Server-written, not set by builders: `PlayerCount` (number) on the portal Model, refreshed per `Config.Lobby.PortalPlayerCountRefresh` | 1 per portal | No `LabelAnchor`: board above `PrimaryPart`. A separate tag is not needed: the board belongs to exactly one portal, so a named child avoids pairing tags. |
| Group chest | `GroupChest` | Station | — . Rewards in `Config.Economy` | 1 | 0: warn, no chest. More than 1: warn, all work; the claim is once per player on the server anyway. |
| News board | `NewsBoard` | BasePart; code puts the text on its `Front` face | — | 1 | 0: warn, no board. More than 1: all show the same text. |
| VIP corner | `VipCorner` | BasePart(s), `CanCollide` off: their boxes together are the corner volume. Doors and decor stay untagged | — . Access from the VIP pass (`Config.Monetization`) | at least 1 if the corner exists | None: warn, no VIP corner. How non-VIP players are kept out is #37's call. |

The leaderboard boards between the portals (7.2) are #44's and follow the same pattern there.

### StreamingEnabled

| Need | How |
|---|---|
| Server bindings (triggers, prompts, purchases, find spawns, teleports) | The server always has the whole map. Every state-changing binding is server-side. |
| Client labels, prompts and effects at a station | The client binds through `GetInstanceAddedSignal`/`GetInstanceRemovedSignal` and drops the binding when a station streams out. Stations are `ModelStreamingMode = Atomic`, so `PrimaryPart`, `LabelAnchor` and the visuals arrive together. Nobody needs a label they are too far away to see. |
| Client needs a position while it may be streamed out | The server publishes the position as a Vector3 attribute, as with `BallScaleAnchor` (Player attribute, ADR 0002). Static Lobby positions go on `Workspace` once at server start; per-player targets on the `Player`. Expected case: the first-join arrow to the Singleplayer portal (#42). |
| Zone of a streamed part | Resolved from the area root, which always replicates (see "Zone number"). |

**Not used:** `ModelStreamingMode = Persistent`. It would keep every station of every zone in memory on every client, against the mobile budget (ADR 0003 R2), and a builder could forget to set it. Publishing the few positions the client really needs is cheaper and explicit.

### Where the names live in code

The feature issues put the names they use into `src/shared/Config/*`, not this ADR's PR. Proposal: one `Config/Map` module for the new tags, attribute names and `LabelAnchor`, created by the first feature that needs it. The existing names stay where they are (`Config.Ball`). A shared resolver (`ZoneIndex` lookup, `Workspace.Map` scope, warn once) belongs in the first of #39/#40 that needs it.

## Consequences

- Builders tag stations, anchors and areas without code changes, and code works with streamed parts.
- Design values exist only in Config and Formulas, so a price or egg change never touches a map file.
- A built zone in `main` stays closed until the cap is raised in a reviewed PR, so #104 can merge before #105 without opening zone 6.
- `Placeholder` has no `ZoneIndex`. It keeps working for surfaces, obstacles and `ScaleAnchor`; zone-bound features need real zone areas (#29) or a `ZoneIndex` on a test area.
- The current `ScaleAnchor` lookup (`BallService/BallAttributes`) does not filter to `Workspace.Map`. Kit templates must not carry `ScaleAnchor` until #38 adds that filter.
- Stations must be Models with `PrimaryPart` and `Atomic` streaming. An exported area that loses `PrimaryPart` shows up as a warning at start, not as a silent dead station.
- New tags and attributes after this ADR need an ADR update or a note in the feature PR that adds them.

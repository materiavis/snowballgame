# 0003 — Snow Rush technical intake

**Status:** Proposed
**Plan revision:** 1
**Concept:** [❄️ 02 - Snow Rush](https://app.notion.com/p/3f9c1165e2b98133a597c16e25cbffbc) (page ID `3f9c1165-e2b9-8133-a597-c16e25cbffbc`) · v5 (Stand 2026-10-15, v5 Freigabe 2026-10-22) · last edited 2026-10-22T17:08:01Z
**Concept approval:** Section 0 records status **Freigegeben für Development** on 2026-10-22, approved by all four owners: Marco Lecluse, Miguel Covas, Jan Reimer and Yowaldy Keller (Notion user IDs resolved via workspace user list). Claude entered the approval on Miguel's instruction (change log "v5 Freigabe"). Repository field: `materiavis/snowballgame`, which matches `origin` (`https://github.com/materiavis/snowballgame.git`).
**Repository:** materiavis/snowballgame · analysis commit `d00991d4f9497c9a36f21898179d3b08f4f65879` (`origin/main`)
**Intake validation:** 2026-10-22. All nine items under *Checkliste vor der Freigabe* are checked. Every chapter-7 launch feature plus 9.6, 10.1 and 10.2 has *Fertig, wenn …*, *Fix* and *Spielraum*. Controls (6.3), save data (12.1), edge cases (6.5), policy review (13, R1, R6), asset rights (11), launch/later split (15.2) and the cut list (15.3) all have content. Section 17 has no question marked *Blockiert Development* (its legend says "Bei Snow Rush: keine"). Nonblocking items Q2, Q6, Q7, Q9, Q14, Q15 and Q16 and the risks R1 and R3 to R6 keep their owners and defaults. Q11 and R2 are *Development darf entscheiden* (see Open questions). Workflow decisions were read from [Entscheide AI-Workflow](https://app.notion.com/p/3f9c1165e2b981be97b6ccda648e71a8), last edited 2026-10-15.

## Context

Snow Rush is a single Roblox experience with three kinds of Place (concept 5.6):

- a summer **Lobby** with two portals,
- a **Simulator** (one Place per world, only World 1 at launch, about 10 players per public server, each player progressing on their own),
- a **Snowball Fight Arena** on reserved servers per match (2v2, 3v3, 4v4, with bots filling free slots).

The concept defines *what* to build. Architecture, modules, remotes, data model, persistence library, ball physics, teleports, matchmaking and bot pathfinding are delegated to Development (concept 1.1 and 4.3).

The repository today has only the scaffold:

- one `default.project.json`,
- `src/server/init.server.luau`, which starts `Services/*`,
- `src/client/init.client.luau`, which starts `Controllers/*`,
- `src/shared/Config.luau`,
- CI that runs StyLua, Selene and a Rojo build of `default.project.json`.

Existing related work, all built against the older "SCHNEEBALL GAME" notes rather than this concept:

| Item | State | Relation to this plan |
|---|---|---|
| [#3](https://github.com/materiavis/snowballgame/issues/3) / [PR #7](https://github.com/materiavis/snowballgame/pull/7) Prototype: growing snowball physics | Open. PR head `fd6c9d2`, last updated 2026-10-09, Studio playtest still open | Prototype milestone. It provides `BallService`, `BallController` and `BallConfig`, plus ADR 0002 (on the PR branch, which is why this ADR is 0003). It still uses a "×N" label and growth per stud. The concept now requires meters/km, zone maximum sizes, time-based growth targets and zone optics. These changes are planned in `7.3-ball-push` and `7.4-ball-growth`. |
| [#8](https://github.com/materiavis/snowballgame/issues/8) Growth only while the character is near the ball | Open | Implements one 7.4 criterion ("Entfernt sich die Figur vom Ball, wächst er nicht"). It is recorded as existing partial work for `7.4-ball-growth`, not duplicated. |
| [#4](https://github.com/materiavis/snowballgame/issues/4) Mobile check: ball prototype | Open, Jan | Prototype milestone evidence for Visual Cap (7.3, R2). |

The 15 October workflow decisions apply here:

- map areas are versioned as `.rbxmx` in Git and mapped through Rojo,
- one editor works on an area at a time, with export/PR handoff,
- terrain is solved separately,
- Miguel and Yowaldy review this plan,
- the Development Manager merges only into non-`main` branches,
- the build loop allows three correction rounds.

## Decision

### Architecture and responsibilities

**Principles**
- **The server is authoritative** (CLAUDE.md §6, concept 5.4/6.5). Clients send intents only: move (through physics ownership of their own ball), throw, buy, equip, trade, claim. The server owns size, coins, Snow Coins, rolls, hits, scores and purchases.
- **Networking.** One `Net` module in `src/shared/Net` declares every remote with an argument schema and a per-player rate limit. The server creates the instances under `ReplicatedStorage.Remotes` and wraps each handler in validation for type, range, ownership and rate. A failed validation drops the call and is counted for analytics. It never throws to the client.
- **Configuration.** All numbers live in `src/shared/Config/*` modules (concept 1.2, 5.4.6). Formulas are pure functions in `src/shared/Formulas/*`, so they can be unit-tested and the client can show previews. The server always recomputes.
- **Persistence.** Only `DataService` touches DataStoreService (CLAUDE.md §6). That includes the OrderedDataStores for global leaderboards and the trade ledger. Cross-server, short-lived state uses MemoryStoreService through one `MatchmakingStore`/`PresenceStore` module: queue, presence counts, match records and private-server mapping. When `game.PlaceId == 0`, every store is an in-memory fake. This keeps Studio test runs (`build/test.rbxl`) away from production data (CLAUDE.md §9).
- **Mobile performance (R2).** Rendering that only one player needs stays on that client: pets following, per-player finds, per-player snow track, VFX. The server keeps state, rolls and validation. Foreign pets and balls use simplified rendering and respect "Weniger Effekte".
- **StreamingEnabled** is on in every Place (3.1). Client code waits for streamed instances through CollectionService tags instead of fixed paths.

**Startup.** `init.server.luau` and `init.client.luau` keep their pattern. They additionally start modules from optional `PlaceServices` / `PlaceControllers` folders that each Place's Rojo project mounts (next section). Services expose `Start()`. `DataService` and `Net` initialise first because other services await them (`DataService.WhenProfileLoaded(player)`).

| Component | Server/client/shared | Responsibility | Dependencies | Concept section |
|---|---|---|---|---|
| `Net` + remote schemas | shared + server | Remote registry, validation, rate limits | — | 6.5 |
| `Config/*`, `Formulas/*`, `NumberFormat`, `Rarity` | shared | Startwerte, formulas, K/M/B/T/Qa/Qi/Sx, m/km formatting, rarity colour + stars | — | 1.2, 8.3, 8.5, 10.3 |
| `PlaceInfo` | shared | Place role and world index from Workspace attributes set by Rojo. PlaceIds are placeholders filled by humans | — | 5.6 |
| `DataService` | server (all Places) | Profiles, schema/migrations, session lock, autosave 2 min, save on leave and before teleport, immediate saves, ordered stores, deletion requests | DataStoreService | 6.5, 12.1 |
| `Rng` | shared (pure) + server | Seeded weighted rolls (`Random`), odds tables, luck modifier | Config | 7.7, 7.9, 8.5 |
| `CurrencyService` | server | Coins, total earned coins, Snow Coins. All mutations go through it and are logged as analytics economy events | DataService | 8.1 |
| `TravelService` | server (all) | Teleports with save-then-teleport, retries, failure messages, Studio stub | DataService, PlaceInfo | 5.6, 6.5 |
| `PurchaseService` | server (all) | `ProcessReceipt` exactly once, game pass ownership cache, Premium, effects registry | DataService | 9.1–9.6, 6.5 |
| `BoostService` | server (all) | Boost remaining time, ticking only while the player is in game, extend on re-buy | DataService | 9.3, 6.5 |
| `SettingsService` | server (all) | Persisted settings (music, sound, graphics, fewer effects, trade requests) | DataService | 10.2, 12.1 |
| `AnalyticsService` (wrapper) | server (all) | Funnel/progression/economy/custom events listed in 12.2 | — | 12.2 |
| `LeaderboardService` | server (all) | Server and Global views per mode, top 50, ≤5 min refresh, own row, bots/private excluded | DataService | 7.2 |
| `AnnouncementService` | server (Lobby, Sim) | Server-wide banners, max 1 per 10 s | — | 7.24 |
| `PetService` | server (Lobby, Sim) | Inventory, equip/best, delete, merge Gold, Frosty, slots, inventory expansion | DataService, Rng | 7.9 |
| `TradeService` | server (Lobby, Sim) | Requests, privacy, offer state machine, ready + 5 s countdown, atomic swap via ledger | PetService, DataService | 7.23, 6.5 |
| `LobbyService`, `PortalService`, `GroupChestService` | server (Lobby) | Spawn, portal countdown/teleport, portal player counts, group chest once | TravelService, PresenceStore | 7.1 |
| `MatchmakingService` | server (Lobby, Arena) | Mode queues, parties (team platform), 30 s timer, level balancing, reserve server, backfill | MemoryStore, TravelService | 7.14 |
| `BallService` (from PR #7, extended) | server (Sim) | Ball spawn/ownership, growth by surface/zone, collisions, knock-over, size in meters | Config, ZoneService | 7.3, 7.4 |
| `SurfaceService` | server (Sim, Arena) | Tag-based surface lookup (Snow, DeepSnow, Ice, Grass), per-player track grid with 20 s regrowth | — | 6.2, 7.4 |
| `FindService` | server (Sim) | Per-player spawn points, rolls, magnet pickup, collection log | Rng, DataService | 7.7 |
| `SellService` | server (Sim) | Scale contact, coin formula with all bonuses, auto-sell pass | Formulas, CurrencyService, PetService, BoostService | 7.5, 8.3 |
| `ZoneService` | server (Sim) | Zone max sizes, barrier purchase, zone teleport, world gate, last zone | CurrencyService, DataService, TravelService | 7.6 |
| `UpgradeService` | server (Sim) | 5 upgrades × 100 levels, cost formula, effects | CurrencyService | 7.8 |
| `EggService` | server (Sim) | Egg prices, hatch (1/3/auto), odds display incl. luck boost | Rng, PetService, CurrencyService | 7.9 |
| `RebirthService` | server (Sim) | Eligibility, reset rules, multiplier, ranks | CurrencyService, UpgradeService | 7.10 |
| `EventService` | server (Sim) | Fresh Snow / Golden Snow per-server schedule, purchasable extra Fresh Snow | AnnouncementService | 7.11 |
| `DailyRewardService` | server (Sim) | UTC day streak, income-per-minute rewards, live day change | Formulas, BoostService, EggService | 7.12 |
| `OverheadService` | server (Sim) | Rank + highest zone above players | DataService | 7.24 |
| `MatchService` | server (Arena) | Match record lookup, arena load, countdown, score, timer, overtime, AFK, results, replay/lobby | MatchmakingStore, TravelService | 7.15, 7.21 |
| `CombatService` | server (Arena) | Ammo, reload on snow, throw validation, server projectile simulation, hits, freeze, spawn protection | SurfaceService | 7.16 |
| `PowerupService`, `SignalService`, `BotService`, `ArenaRewardService`, `CosmeticService` | server (Arena; cosmetics also Lobby) | 7.18, 7.17, 7.22, 7.20 | CombatService, CurrencyService | 7.17–7.22 |
| Controllers | client | `InputController` (last-used device, prompts, binds), `HudController`, `MenuController` (window stack, close via X/menu key/B), `CameraController`, `BallController`, `PetFollowController`, `TutorialController`, `ShopController`, `TradeController`, `LeaderboardBoardController`, `CombatController` (aim, aim assist on touch/gamepad), `ResultController`, `AnnouncementController` | Net | 3.2, 6.3, 10.1–10.3 |

**Alternatives considered**
- **Persistence library.** A vendored, pinned ProfileStore (MIT) gives proven session locking and teleport handoff. An in-house `UpdateAsync` lock gives full control and no third-party code. **Decided (D1):** in-house, built on `UpdateAsync` with a lock token, lock timeout and forced steal after the timeout. It stays small and auditable, and the trade ledger needs custom hooks anyway.
- **Ball collisions with foreign characters.** 7.3 and 6.1 require that characters walk through foreign balls. Per-player collision groups would need two groups per player, with a limit of 32 groups. **Proposal:** each client sets `CanCollide = false` on foreign balls locally. Characters are client-simulated, so this is enough, and the server keeps the shared `SnowBalls` group (PR #7) for ball-vs-ball.
- **Arena match configuration.** Teleport data passes through the client and is not trusted. The Arena server looks up its match record (mode, teams, parties, arena, private flag) in MemoryStore, keyed by `game.PrivateServerId` of the reserved server.

### Places, Rojo and world assets

| Place | Purpose | Rojo project file | Source paths and Roblox mappings | Teleport boundary |
|---|---|---|---|---|
| Lobby | Start map, portals, leaderboards, chest, trading, shop | `places/lobby.project.json` | `src/shared`→`ReplicatedStorage.Shared`; `src/server`→`ServerScriptService.Server`; `src/places/social/server`→`…Server.SocialServices`; `src/places/lobby/server`→`…Server.PlaceServices`; `src/client`→`StarterPlayerScripts.Client` (+ `src/places/social/client`, `src/places/lobby/client` as `SocialControllers`/`PlaceControllers`); `world/lobby/*.rbxmx`→`Workspace.Map.*`; Workspace `$attributes` `PlaceRole="Lobby"`; `StreamingEnabled=true` | → Simulator (portal, last world/zone); → Arena (match start); ← from both |
| Simulator World 1 | Zones 1–10 | `places/world1.project.json` | shared/server/client as above; `src/places/social/*`; `src/places/simulator/{server,client}` (shared by all worlds); `world/world1/*.rbxmx`→`Workspace.Map.*`; `world/kits/world1.rbxmx`→`ServerStorage.Kit`; `PlaceRole="Simulator"`, `WorldIndex=1` | → Lobby (Lobby button); → World 2 (world gate, closed at launch) |
| Simulator Worlds 2–5 (later) | Zones 11–50 | `places/world2.project.json` … (added with each world) | Same code; own `world/worldN` | Gate chain |
| Arena | One match per reserved server | `places/arena.project.json` | shared/server/client; `src/places/arena/{server,client}`; `world/arena/*.rbxmx`→`ServerStorage.Arenas.*` (MatchService clones one per match); `PlaceRole="Arena"` | → Arena (Replay, via queue); → Lobby |

Proposed tree (created by `x-multi-place-rojo`):

```
places/{lobby,world1,arena}.project.json
src/shared/{Config,Formulas,Net,...}     # all Places
src/server/Services/*                    # core services, all Places
src/client/Controllers/*                 # core controllers, all Places
src/places/social/{server,client}        # Lobby + Simulator (pets, trading, shop, announcements)
src/places/lobby/{server,client}
src/places/simulator/{server,client}     # every Simulator world
src/places/arena/{server,client}
world/lobby/*.rbxmx  world/world1/*.rbxmx  world/arena/*.rbxmx  world/kits/*.rbxmx
```

**Build and serve per Place.** Only one Place is open in Studio at a time, always at `build/test.rbxl` with `game.PlaceId == 0` (CLAUDE.md §9):

```
rojo build places/lobby.project.json  -o build/test.rbxl   # rojo serve places/lobby.project.json
rojo build places/world1.project.json -o build/test.rbxl   # rojo serve places/world1.project.json
rojo build places/arena.project.json  -o build/test.rbxl   # rojo serve places/arena.project.json
```

CI builds each project to its own file (for example `build/ci-lobby.rbxl`), because CI never opens Studio. Formatting and lint also cover `src` and any test folder.

**Migration (decided, D2).** `default.project.json` and the current DoD command stay unchanged until the `x-multi-place-rojo` issue. That issue's PR changes three things together:
- the Rojo mapping (what happens to `default.project.json`),
- CI,
- the build command in CLAUDE.md's Definition of Done.

Because it changes repository rules, that PR needs human review.

**Live PlaceIds** for teleports live in `Config/Places` as `0` placeholders. Humans fill them at publish. Agents never publish (CLAUDE.md §9).

**Teleports in Studio.** Teleports don't work there, so `TravelService` runs as a stub when `PlaceId == 0`. It logs the destination and payload and reports success or a simulated failure. The playtester verifies the intent, and real teleports are checked on the human-published test version.

**Map areas (`.rbxmx`, one editor per area, export + PR before the next editor works on it).** These boundaries are proposed for review:

| Area file | Rojo target | Content | Editor (proposal) |
|---|---|---|---|
| `world/lobby/Village.rbxmx` | `Workspace.Map.Village` | Houses, fountain, deco (Creator Store allowed after `model-auditor`) | Miguel or Yowaldy |
| `world/lobby/Plaza.rbxmx` | `Workspace.Map.Plaza` | Spawn, portals, team platform, boards, chest, news board, VIP corner, tagged anchors | Miguel or Yowaldy |
| `world/world1/Zone01.rbxmx` … `Zone10.rbxmx` | `Workspace.Map.ZoneNN` | Ground, deep snow, obstacles (tagged knock-over size), find points, station anchors, barrier | One editor per zone |
| `world/kits/world1.rbxmx` | `ServerStorage.Kit` | ~20 kit parts (Creator Store allowed after audit) | Miguel or Yowaldy |
| `world/arena/SnowySquare.rbxmx`, `FrozenLake.rbxmx` | `ServerStorage.Arenas.*` | Mirrored bases, cover, power-up points, 2v2 barriers | One editor per arena |
| `assets/stations/*.rbxmx`, `assets/pets/*.rbxmx`, … | `ReplicatedStorage.Assets.*` | Self-built signature assets (11) | Asset owner |

Gameplay code binds to the maps only through CollectionService tags and named anchor attachments. Builders can then iterate without code changes, and code works with streamed parts.

**Terrain (decided, D3).** Gameplay ground is built from parts and meshes tagged `Snow`, `DeepSnow`, `Ice` or `Grass` inside each area `.rbxmx`, not from Roblox Terrain voxels. This has four benefits:

- it fully diffs in Git,
- surface lookup is deterministic,
- areas don't overlap a single global Terrain object,
- the per-player snow track (7.4) is a logical grid that never edits shared geometry.

Decorative backdrop terrain (mountains around zones) is generated at server start from a small config-driven script. A `TerrainRegion` snapshot (`world/<place>/Backdrop.rbxmx`) is taken only at milestones if hand-sculpted terrain is wanted.

### Data model and failure behaviour

This is a **new** save format (schema version 1). It does not change a live format. Approving this plan approves the format (CLAUDE.md §13). Any later change gets a migration step and owner escalation.

| Data | Type/default | Owning service | Persistence and scope | Concept section |
|---|---|---|---|---|
| `schemaVersion` | number = 1 | DataService | Profile | — |
| `settings` | {music, sound, graphics, fewerEffects: bool, tradeRequests: "all"/"friends"/"off"} | SettingsService | Profile | 10.2, 12.1 |
| `tutorial` | {seenSingleArrow, seenMultiArrow, hints: {[id]=true}, firstMatchHints} | TutorialController/LobbyService | Profile | 7.1, 10.1 |
| `groupChestClaimed`, `lastMode` | bool=false, string | GroupChestService, TravelService | Profile | 7.1, 12.1 |
| `boosts` | {[boostId]=remainingSeconds} | BoostService | Profile; ticks only while online in any Place | 9.3, 6.5 |
| `sim.coins`, `sim.totalCoins` | number = 0 | CurrencyService | Profile + ordered store (`totalCoins`) | 8.1, 7.2 |
| `sim.upgrades` | {growth, walkSpeed, magnet, sellValue, stability: 0..100} | UpgradeService | Profile | 7.8 |
| `sim.unlockedZones`, `sim.lastWorld`, `sim.lastZone`, `sim.highestZone` | set/number | ZoneService | Profile (barrier → save immediately) + ordered store | 7.6 |
| `sim.rebirths` | number = 0 | RebirthService | Profile (immediate) + ordered store | 7.10 |
| `sim.pets` | {[uid]={kind, variant: "normal"/"gold"/"rainbow", frosty: bool, equipped: bool}}; `inventorySize`=50 | PetService | Profile. The unique `uid` makes duplication detectable | 7.9 |
| `sim.collection` | {finds: {[findId]=firstTime}, pets: {...}, zones: {...}} | FindService | Profile from launch (book is later) | 7.7, 7.13 |
| `sim.records`, `sim.titles`, `sim.stats` | biggest ball, most coins in one ball, titles, counters | various | Profile | 12.1 |
| `sim.daily` | {streakDay, lastClaimDay (UTC day index)} | DailyRewardService | Profile | 7.12 |
| `sim.ballSkins`, `starterPackBought` | set/bool | PurchaseService | Profile | 9.3 |
| `sim.tradeHistory` | ring buffer of 50 {tradeId, partner, gave, got, time}; `pendingTradeId` | TradeService | Profile | 7.23 |
| `fight.snowCoins`, `fight.xp`, `fight.level`, `fight.wins`, `fight.losses`, `fight.freezes` | numbers | ArenaRewardService | Profile + ordered stores | 7.20, 7.2 |
| `fight.cosmetics` | {owned set, equipped per slot} | CosmeticService | Profile | 7.20 |
| `purchases.receipts` | bounded map of processed `PurchaseId`s | PurchaseService | Profile, saved before granting | 9.6, 6.5 |
| Ball size and finds currently in the ball | — | BallService | **Not saved**: lost on leave (6.5) | 6.5 |

**Rules**
- **Session locking.** Each profile key holds `{lockServer, lockTime}` written through `UpdateAsync`. Another server waits and retries up to a timeout, then steals a stale lock. Before a teleport, the server saves, releases the lock and only then teleports (6.5: stay in place with a message if the save fails). The destination waits for the release.
- **Load failure.** The player is never given a blank profile that would overwrite saved data. In the Lobby they see a notice and the portals stay locked (6.5). In other Places the server retries, then returns them to the Lobby.
- **Saving.** Autosave every 2 min, on leave and on `BindToClose`. Immediate save for Robux purchases, paid barriers, rebirths and completed trades. A write never overwrites a newer state: each save carries a monotonically increasing `saveSeq`, checked inside `UpdateAsync`.
- **Purchases (exactly once).** `ProcessReceipt` checks `purchases.receipts[PurchaseId]`, applies the grant, records the id, saves, and returns `PurchaseGranted` only after the save succeeds. Otherwise it returns `NotProcessedYet`. Game passes are cached per session, refreshed on `PromptGamePassPurchaseFinished`, and take effect immediately in any Place.
- **Trades (two profiles, no double or lost pet).** Two-phase commit through a `TradeLedger` DataStore owned by DataService:
  1. Write `pendingTradeId` into both profiles and save both.
  2. Write the ledger entry `committed` with both item lists.
  3. Apply the swap in memory, append to history, clear `pendingTradeId`, and save both.

  On every profile load, a non-empty `pendingTradeId` is reconciled against the ledger: committed and not applied → apply; absent → clear. Ownership and inventory space are re-checked at step 1 (6.5, 7.23). This satisfies "gilt erst, wenn für beide gespeichert" without assuming cross-key atomicity.
- **Global leaderboards.** OrderedDataStores accept only integers below 2^63, but coins reach Sx (1e21). Large values are stored as `floor(log10(v) × 1e6)` and decoded for display. Integers are stored raw for zones, rebirths, wins, freezes and level. Writes happen at most on autosave. Bots and private servers never write (7.2).
- **Deletion requests (12.1).** `DataService.EraseUser(userId)` removes the profile and ordered-store entries. Owners run it after a Roblox right-to-erasure request. It is exposed only as an owner-run admin script, never as a remote.
- **Cross-server ephemeral state (MemoryStore).** This covers queues, parties, match records (TTL), portal presence counts (TTL 60 s, refresh ≤30 s) and the mapping from private server to reserved Simulator server. Losing it never loses progress.

### Milestones (concept 15.1)

The concept gives months and phrases, not calendar dates. GitHub `due_on` stays unset and the concept wording goes into the milestone description.

| Concept milestone | Required outcome | Actual target date or unset | Existing GitHub milestone |
|---|---|---|---|
| Konzept freigegeben | Checklist complete, all four owners read it ("Erledigt am 22.10.2026") | unset (concept: "So bald wie möglich", done 2026-10-22) | none. Create it open with no issues. Humans close it (decided, D4) |
| Prototyp | Ball prototype PR #7: push and growth, Visual Cap and MaxCountedSpeed fixed. Building blocks: saving, currency, randomness, upgrades, config modules | unset ("Anfang November 2026") | none |
| Vertical Slice | Lobby with portals and teleports, Simulator zones 1–5 on multi-player servers, with selling, barriers, upgrades and Egg 1, saving, tested on mobile | unset ("November 2026") | none |
| Interner Test | Owner playtest, mobile check, test with children | unset ("Ende November 2026") | none |
| Testversion ab 16 | Published, questionnaire filled, analytics running | unset ("so früh wie möglich, spätestens Mitte Dezember 2026") | none |
| Freigabe für alle Altersstufen | Roblox review done | unset ("Januar 2027, spätestens 60 Tage nach der Testversion") | none |
| Launch | Launch scope 15.2 complete | unset ("Februar 2027") | none |

Updates 1–6 (15.2) are **not** 15.1 milestones. Later features get no milestone and are marked `later` in the issue (decided, D5: no roadmap milestones).

**Rule for features that span milestones (decided, D6, option A).** A feature gets exactly one issue (intake rule). The issue goes into the **earliest** milestone whose outcome needs it, and the issue body names that milestone's minimum slice. Example: `7.9-pets-eggs` sits in Vertical Slice because Egg 1 is needed, while Egg 2, Gold, Frosty and trading readiness complete before Launch.

### Feature coverage and proposed issues

"Agent" uses the existing agents. Existing labels are only `task`, `gameplay`, `mobile` and `documentation`. The `systems` and `ui` labels, which the systems-engineer and ui-engineer agent definitions refer to, do not exist yet. Yowaldy creates them (Q-L). Issue creation uses them only once they exist. Map building and assets are human work by Miguel and Yowaldy (concept 14). Issues note this, and agents work against tagged placeholder geometry until real areas land.

Rows marked **prereq** are not chapter-7 features. Each is derived from a cited concept or repository requirement and needed by several features. They are listed for review.

| Feature key | Concept section | Launch/later | Milestone | Scope | Dependencies | Existing issue/PR |
|---|---|---|---|---|---|---|
| `x-multi-place-rojo` (prereq) | 5.6, 3.1, 4.1; workflow decision 15.10. | Launch | Prototyp | Per-Place project files, folder tree, Workspace attributes, StreamingEnabled, init loaders for Place folders, CI builds per Place, `world/` folder with one placeholder area. The same PR changes the `default.project.json` mapping and the CLAUDE.md DoD build command (D2) | — | — |
| `x-net-remotes` (prereq) | 6.5, CLAUDE.md §6 | Launch | Prototyp | `Net` registry, schemas, validators, rate limits, test fakes | x-multi-place-rojo | — |
| `x-test-harness` (prereq) | 4.4 (10,000 egg openings), 7.23 (1,000 trades), 7.5 (exact formula) | Launch | Prototyp | Headless Luau test runner for pure modules (e.g. Lune pinned in `rokit.toml`), CI job | — | — |
| `12.1-player-data` (prereq) | 6.5, 12.1 | Launch | Prototyp | DataService (schema v1, lock, autosave, immediate save, saveSeq, fake store at PlaceId 0, erase), ledger + ordered store access | x-net-remotes | — |
| `8.3-economy-config` (prereq) | 1.2, 8.1–8.5, 10.3 | Launch | Prototyp | Config modules for every Startwert, pure formulas (sizes, values, barriers, eggs, upgrades, rebirth, income/min, bonuses), NumberFormat, m/km, Rarity + RNG, CurrencyService | 12.1-player-data, x-test-harness | — |
| `7.3-ball-push` | 7.3 | Launch | Prototyp | Extend PR #7: zone optics `4 + 0.94 × (zone − 1)` studs, 40→100 % within zone, push speed follows walk speed/upgrade/pass, jump off in Simulator, foreign balls non-colliding for characters, camera auto-zoom | PR #7 merged, x-multi-place-rojo | #3, PR #7 |
| `7.4-ball-growth` | 7.4, 6.2 | Launch | Prototyp | Size in meters, start 10 %, time-to-max via Growth upgrade, surfaces (deep ×2, track 20 s per player), collisions −10 %/1 s protection, knock-over ≥3×, MAX state, m/km display | 7.3-ball-push, 8.3-economy-config | #8 (proximity criterion) |
| `7.8-upgrades` | 7.8 | Launch | Prototyp | UpgradeService, menu (U/button/D-pad right), before/after display, upgrade stand | 8.3-economy-config, 10.2-hud-menus | — |
| `x-travel-teleports` (prereq) | 5.6, 6.5 | Launch | Vertical Slice | TravelService: save→release→teleport, retry, failure message, Studio stub; Simulator server selection (free slot, friend preference, overflow), Lobby button | 12.1-player-data | — |
| `10.2-hud-menus` | 10.2, 3.2, 6.3, 10.3 | Launch | Vertical Slice | HUD layouts per Place, window stack, close X/key/B, 44 px, ≤⅔ screen, last-device prompts, settings window incl. "Weniger Effekte" | x-net-remotes | — |
| `6.2-world1-zones` (prereq) | 6.2, 7.6, 11 | Launch | Vertical Slice (zones 1–5), zones 6–10 by Launch | Zone area files, tags, anchors, kit audit; human-built with agent support | x-multi-place-rojo | — |
| `7.1-lobby-portals` | 7.1 | Launch (season decor later → `7.1b`) | Vertical Slice | Lobby area, portals + countdown, mode window, player counts, first-join arrow, group chest, news board, VIP corner | x-travel-teleports, 10.2-hud-menus | — |
| `7.5-selling` | 7.5, 8.3 | Launch | Vertical Slice | Scale, exact formula incl. bonuses, "+3.4K" fly-to-HUD, reset to start size | 7.4-ball-growth | — |
| `7.6-zones-barriers` | 7.6 | Launch | Vertical Slice | Barriers, unlock window, missing amount, persistence, zone teleport (T), world gate closed, last zone | 7.5-selling, 6.2-world1-zones, x-travel-teleports | — |
| `7.7-finds` | 7.7 | Launch | Vertical Slice | Per-player spawn points, odds incl. zones 1–5 rule, secret find, stuck-in-ball visuals, collection log | 7.4-ball-growth, 8.3-economy-config | — |
| `7.9-pets-eggs` | 7.9 | Launch (rainbow/secret → `7.9b`) | Vertical Slice (Egg 1); full launch scope by Launch | Eggs 1–2, odds display, hatch anim, slots, Best Equip, delete, Gold merge, Frosty, following in Lobby/Sim, inventory expansion (Q11) | 8.3-economy-config, 12.1-player-data | — |
| `10.1-onboarding` | 10.1 | Launch | Vertical Slice | Arrows, animated hand, one-time hints, saved state, first match symbols | 7.1-lobby-portals, 7.5-selling | — |
| `12.2-analytics` | 12.2 | Launch | Testversion ab 16 | AnalyticsService events for every listed measurement point | x-net-remotes | — |
| `7.2-leaderboards` | 7.2 | Launch (season boards → `7.2b`) | Launch | Lobby, World start and Arena boards, Server/Global filter per viewer, own row, 5 min refresh | 12.1-player-data | — |
| `7.10-rebirth` | 7.10 | Launch | Launch | Button from zone 10, confirm window, reset rules, +0.5 multiplier, ranks | 7.6-zones-barriers, 7.8-upgrades | — |
| `7.11-events` | 7.11 | Launch | Launch | Fresh Snow 15 min/2 min, Golden Snow ~60 min/1 min, countdown, extra Fresh Snow product hook | 7.4-ball-growth, 7.5-selling | — |
| `7.12-daily-rewards` | 7.12 | Launch (daily quests → `7.12b`) | Launch | 7-day streak, UTC, income-based coins, boosts, Day 4 egg, Day 7 epic pet, luck boost odds | 7.9-pets-eggs, 9.3-developer-products | — |
| `7.23-pet-trading` | 7.23 | Launch | Launch | Requests/privacy/spam limit, window (8/side, sums), ready + countdown, ledger swap, unlock at zone 5, history, warning text | 7.9-pets-eggs, 12.1-player-data | — |
| `7.24-chat-visible-progress` | 7.24, 13 | Launch | Launch | TextChatService on in all Places, overhead rank + zone, server announcements (≤1/10 s), chat-free playability check | 7.10-rebirth (ranks), 7.9-pets-eggs | — |
| `7.14-matchmaking` | 7.14 | Launch | Launch | Mode window, queues, team platform parties, level balance, 30 s start, bots fill, reserve + teleport, leave queue | x-travel-teleports, 7.1-lobby-portals | — |
| `7.15-match-flow` | 7.15 | Launch | Launch | Modes table, teams + icon, scoring, overtime, countdown, AFK 60 s, HUD score | 7.14-matchmaking | — |
| `7.16-throwing` | 7.16 | Launch | Launch | Ammo/reload on snow, arc throw 80 studs/0.35 s, server projectiles, 5-hit freeze, recovery, no friendly fire, aim assist touch/gamepad, shift-lock | 7.15-match-flow | — |
| `7.17-quick-signals` | 7.17 | Launch | Launch | 4 signals, team-only, 3 s display, 2 s cooldown | 7.15-match-flow | — |
| `7.18-powerups` | 7.18 | Launch (more → `7.18b`) | Launch | 4 power-ups, 30 s spawn, one at a time, contested pickup | 7.16-throwing | — |
| `7.19-arenas` | 7.19 | Launch (Glacier Fortress → `7.19b`) | Launch | Snowy Square + Frozen Lake, mirrored bases, 2v2 barriers, breakable walls 3 hits/15 s | 7.15-match-flow | — |
| `7.20-fight-progression` | 7.20 | Launch (quests/more cosmetics → `7.12b`, `7.20b`) | Launch | Snow Coins rules, XP/levels 1–100 (L10 ≈ 20 matches), level badge, cosmetic shop ~10 items, visibility | 7.15-match-flow | — |
| `7.21-results-screen` | 7.21 | Launch | Launch | Results ≤2 s, MVP (no bots), stats, Replay for group, To Lobby | 7.20-fight-progression, 7.14-matchmaking | — |
| `7.22-bots` | 7.22 | Launch | Launch | Snowman bots with BOT label, pathfinding, 40 % accuracy, 0.8 s pause, replace leavers/no-shows, config switch | 7.16-throwing | — |
| `9.2-gamepasses` | 9.2 | Launch (2x XP → `9.2b`) | Launch | 9 launch passes and their effects in each system | 8.3-economy-config, 12.1-player-data | — |
| `9.3-developer-products` | 9.3 | Launch (season pass → `9.4b`) | Launch | Receipts exactly once, boosts (extend, pause offline), skins, starter pack once, fight cosmetic packs, Instant Fresh Snow | 12.1-player-data, 7.11-events | — |
| `9.4-premium-private-servers` | 9.4 | Launch | Launch | Premium +10 %, trail, badge, Premium prompt only from shop; private lobby → own Simulator servers and bot-less matches, ≥2 players, uneven teams, ×0.5 Snow Coins, no leaderboards | 9.2-gamepasses, 7.14-matchmaking | — |
| `9.6-shop` | 9.6 | Launch | Launch | Shop button (Lobby/Sim), tabs, item cards, "Owned", active boosts with remaining time, no unsolicited prompts | 9.2-gamepasses, 9.3-developer-products, 10.2-hud-menus | — |
| `x-release-mobile-checks` (prereq) | 4.4, 3.1, CLAUDE.md §14 | Launch | one issue per release milestone: Interner Test, Testversion ab 16, Launch | Jan's mobile check (label `mobile`, assigned to Jan). Blocks the release | per milestone content | #4 (prototype only) |
| `7.1b-seasonal-decor` | 7.1 | Later (first season after launch) | unset | Seasonal Lobby decor by date | 7.1 | — |
| `7.2b-season-leaderboards` | 7.2, 15.2 | Later (Update 4) | unset | Season-scoped boards | 7.2 | — |
| `7.6b-world-2-arctic` | 7.6, 7.7, 7.9, 15.2 | Later (Update 1) | unset | World 2 Place, zones 11–20, Arctic finds, Eggs 3–4, world gate open | 7.6, 7.7, 7.9 | — |
| `7.6c-world-3-himalaya` | 7.6, 7.9, 15.2 | Later (Update 3) | unset | Zones 21–30, finds, Eggs 5–6 | 7.6b | — |
| `7.6d-worlds-4-5` | 7.6, 7.9, 15.2 | Later (Updates 5–6) | unset | Zones 31–50, finds, Eggs 7–10 | 7.6c | — |
| `7.9b-rainbow-secret-pet` | 7.9, 8.5, 15.2 | Later (Update 3) | unset | Rainbow merge, Golden Yeti in eggs from World 2 | 7.9 | — |
| `7.12b-daily-quests` | 7.12, 7.20, 15.2 | Later (Update 1) | unset | 3 daily quests per mode, coin/egg and Snow Coin rewards | 7.12, 7.20 | — |
| `7.13-collection-book` | 7.13 | Later (Update 1). Find storage at launch is in `7.7` | unset | Book UI (C), shadows, "New!", odds page, world completion reward once | 7.7 | — |
| `7.18b-more-powerups` | 7.18, 15.2 | Later (Update 4) | unset | Additional power-ups (content to be specified by Product) | 7.18 | — |
| `7.19b-glacier-fortress` | 7.19, 15.2 | Later (Update 2) | unset | Third arena | 7.19 | — |
| `7.20b-more-cosmetics` | 7.20, 15.2 | Later (Update 1 per 7.20, Update 2 per 15.2, Q-U) | unset | More fight cosmetics | 7.20 | — |
| `9.2b-double-xp` | 9.2 | Later (Update 1) | unset | 2x XP pass | 7.20 | — |
| `9.4b-season-pass` | 9.3, 9.4 | Later (Update 2) | unset | 30-tier pass, free/premium track, retroactive rewards | 7.20, 7.12b | — |

**Excluded, with reasons:**
- Subscription "Snow Rush Plus" and lobby ads (9.4): "Später prüfen", availability open (Q2).
- Avatar items (9.4): a Roblox group marketplace item, not game code.
- Simulator season pass ("später möglich", 9.4): not specified.
- 15.3 cut list: not separate work. It is noted in the affected issues (`7.19`, `7.15`, `7.11`, `7.9`, `7.18`) as the cut order.

**Proposed issue bodies.** Every issue uses `dev-task.md`. The first line is the marker `<!-- intake:concept=3f9c1165-e2b9-8133-a597-c16e25cbffbc;feature=<key> -->`, followed by the concept URL, v5 and the section. Each issue also contains:

- the ADR path and revision,
- launch/later and the milestone from the table,
- **Fix** and **Spielraum** copied verbatim from the concept section,
- the concept's **Fertig, wenn …** criteria copied verbatim and unchecked.

The concept criteria are copied from Notion at creation time, not re-typed here, so they cannot drift. The technical checks below are added to every feature issue and never replace a concept criterion:

- `stylua --check src`, `selene src`, and the Rojo build of each affected Place project pass.
- Server handlers validate type, range and rate (CLAUDE.md §6). No client value is trusted.
- Numbers come from `Config/*`. No hard-coded tuning.
- A Playtester PASS in `build/test.rbxl` (PlaceId 0) for every runtime criterion, or an explicit "pending/human" note for criteria that need live services: real teleports, real purchases, global DataStores, group membership, Jan's phone, children's test, 8 real players.
- For save-relevant issues: the 6.5 edge cases that apply are tested with the fake store, including forced save failure.

Agent per row: `systems-engineer` for prereqs except maps, 12.2, 9.x purchase back-end, 7.14 and 7.23 back-end. `gameplay-engineer` for 7.3–7.12, 7.15–7.19 and 7.22. `ui-engineer` for 10.1, 10.2, 9.6, 7.21 and the 7.2 boards. Maps are human work. `model-auditor` checks any Creator Store asset.

Acceptance criteria for **prereq rows** are derived and need review approval:

- `x-multi-place-rojo`
  - Each Place project builds.
  - Each Place starts its core plus Place services in Studio without errors.
  - CI builds all Places.
  - The existing ball prototype still runs in World 1.
- `x-net-remotes`
  - Malformed, out-of-range and over-rate calls are rejected without errors, and a test proves it.
  - Every remote declares a schema.
- `x-test-harness`
  - `lune run tests` (or equivalent) runs in CI.
  - It covers formula, RNG and trade state-machine modules.
- `12.1-player-data`
  - Every 6.5 row on loading/saving/teleport/server crash passes with the fake store.
  - A forced load failure never writes an empty profile.
  - Session lock contention between two simulated servers resolves without loss.
  - PlaceId 0 never touches real DataStores.
  - Erase works.
- `8.3-economy-config`
  - The tables in 7.6 and 8.4 are reproduced by unit tests (zone 1 barrier ≈ 320, zone 10 ≈ 3.8M, Egg 1 = 240).
  - Number formats match 10.3.
  - A 10,000-roll RNG test is within ±1 percentage point.
- `x-travel-teleports`
  - The Studio stub logs the correct destination for portal, world gate, match start, Replay and To Lobby.
  - A failed save or teleport keeps the player in place with a message and an automatic retry.
- `6.2-world1-zones`
  - Each zone meets the 6.2 build constraints (size, deep snow fields, obstacles, find points, the scale visible from the start).
  - Kit assets have a model-auditor report.
- `x-release-mobile-checks`
  - Jan's checklist from 3.1 performance targets for that release's content is done and the issue is closed.

### Verification plan

**Automated (per PR, CI)**
- StyLua, Selene, and a Rojo build per Place project.
- Headless unit tests (`x-test-harness`) for:
  - formulas: barrier, egg, upgrade, sell with bonuses (×1.4 + ×2.0 + ×3.0 → ×4.4), income/min,
  - RNG distribution (10,000 rolls per egg and find table, ±1 pp),
  - number formatting,
  - the trade state machine (1,000 randomised trades with injected failures: no duplicate or lost uid),
  - DataService locking and `saveSeq` against the fake store.

**Studio playtests (playtester only, `build/test.rbxl`, PlaceId 0, one Place at a time)**
- Per-criterion evidence on the PR head, run as a local server with 2–10 players.
- Coverage: growth timing (40 s ± 3), surfaces, collisions, selling exactness, barrier/zone persistence across a simulated rejoin with the fake store, pets following, trading with disconnect mid-trade, events schedule (shortened by config in test), Arena match flow with bots, AFK and overtime.
- Teleports and purchases are verified at their stub/test boundary only.

**Human, live (cannot be passed by agents; stays pending until done)**
- Real teleports across Places, real Robux purchase plus immediate leave, global leaderboards on the published test version.
- Group chest membership.
- 8 real players in one match.
- Children's test (end of November).
- 4.4 timing targets (zone 2 after ~4 min, zone 10 after 60–90 min).
- Jan's mobile check before each release (CLAUDE.md §14).

**Not performed during intake:** no code, no Studio run, no build. This plan describes future checks only.

## Consequences

- **Order.**
  1. Prototype building blocks: Rojo multi-place, Net, tests, data, economy config, ball push and growth, upgrades.
  2. Vertical Slice: travel, HUD, World 1 zones 1–5, Lobby, selling, barriers, finds, Egg 1, onboarding.
  3. Analytics before the test version.
  4. Then rebirth, events, daily, trading, chat/progress, the whole fight mode and monetisation for Launch, following 15.1's work plan (January).
- **Multi-place cost.** Three Places mean three builds and three Studio sessions per cross-place feature. Playtests serialise on the single Studio. The Studio teleport stub means cross-place flows are fully proven only on the human-published test version.
- **New save format.** Schema v1 is defined before any player data exists, so there is no migration risk now. Later changes need migrations and owner escalation.
- **Trade ledger.** It adds one DataStore read per profile load when `pendingTradeId` is set (rare). That cost is accepted for duplication safety.
- **MemoryStore quotas** scale with concurrent players. Queue polling and presence intervals are config values, to be tuned on the test version.
- **PR #7 rework.** It must be playtested and merged (or superseded) before `7.3`/`7.4`. Its "×N" display and growth-per-stud model are replaced by the concept's meter display and zone model.

## Recorded decisions

Decided by Miguel Covas on 2026-10-22, in an explicit message in the Claude Code intake session, before the first commit of this ADR. These are plan decisions, **not** plan approval. Approval still needs reviews from both Miguel and Yowaldy (below).

| Key | Decision |
|---|---|
| D1 | In-house session locking (`UpdateAsync`, lock token, timeout, steal after timeout), as proposed |
| D2 | `default.project.json` stays until the `x-multi-place-rojo` issue. That issue's PR changes the mapping and the CLAUDE.md DoD build command together |
| D3 | Terrain proposal accepted: tagged parts for gameplay ground, generated backdrop, `TerrainRegion` snapshot only at milestones |
| D4 | Create the "Konzept freigegeben" milestone open with no issues. Humans close it |
| D5 | No roadmap milestones for Updates 1–6. Later issues stay without milestone |
| D6 | Option A: each feature goes into the earliest milestone that needs it, with the slice noted in the issue |
| D7 | New `7.3-ball-push` issue depending on PR #7. #8 is linked as existing partial work for `7.4-ball-growth`. #4 gets the Prototyp milestone (edited only after plan approval) |
| Q-G | 40 s to maximum is measured at the unupgraded pushing speed. Growth is proportional to counted speed up to MaxCountedSpeed. Confirmed in the PR #7 playtest |
| Q11 | Inventory expansion: +10 slots for the value of 10 full balls of the highest unlocked zone, up to 150 slots |
| R2 | Client-side pet/find rendering, simplified foreign pets, lower Visual Cap if PR #7/#4 show instability, "Weniger Effekte" option |
| Q-L | Yowaldy creates the `systems` and `ui` labels |

## Open questions

| Question | Source | Owner | Blocking? | Default/proposal |
|---|---|---|---|---|
| Q-U More cosmetics: Update 1 (7.20) or Update 2 (15.2)? | 7.20 vs 15.2 | Marco (concept) | No | Later, no milestone, until clarified |
| Q-L follow-up: `systems` and `ui` labels exist before issue creation | `.claude/agents` | Yowaldy | No (issues fall back to `task` if missing) | Yowaldy creates them |
| Q2, Q6, Q7, Q9, Q14, Q15, Q16, R1, R3–R6 | 17 | As in concept | No (Blockiert Development nicht) | Concept defaults apply. Q15 default: Instant Fresh Snow is server-wide. Q16 default: only pets tradeable. R6 trade-rule check before the test version |
| Owner for Roblox release and policies (Q6) | 14, 15.1 | All four owners | No for development; yes for the "Testversion ab 16" milestone | Unassigned |

## Manual plan review

Both reviewers must approve the same plan revision before GitHub creation. Only actual human reviews count as evidence. Substantive plan or concept changes require a new revision and renewed approval by both reviewers.

| Reviewer | Approved revision | Review date | Evidence |
|---|---|---|---|
| Miguel | Pending | — | — |
| Yowaldy | Pending | — | — |

## Intake result log

Updated after GitHub operations. This log does not alter the reviewed plan.

| Feature/milestone key | Created/reused/remaining | GitHub URL | Verification or failure |
|---|---|---|---|
| — | No GitHub objects created (plan revision 1 awaiting review) | — | — |

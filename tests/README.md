# Headless tests

Unit tests for pure Luau modules, run with [Lune](https://github.com/lune-org/lune)
(pinned in `rokit.toml`) outside Roblox, locally and in CI.

```sh
lune run tests            # all tests, from the repository root
lune run tests Trade      # only spec files whose path contains "Trade"
stylua --check src tests
selene --config tests/selene.toml tests
```

The runner exits non-zero if any test fails, a spec cannot load, or no test runs.

## Layout

| Path | What |
|---|---|
| `tests/init.luau` | Runner. Finds every `*.spec.luau` under `tests/`. |
| `tests/TestKit.luau` | `suite`, `equal`, `near`, `isTrue`, `throws`. |
| `tests/helpers/SeededRandom.luau` | Deterministic generator (Roblox `Random` does not exist under Lune). |
| `tests/helpers/Distribution.luau` | Chance-table check in percentage points (concept 4.4). |
| `tests/helpers/FakeClock.luau` | Hand-driven clock for code that takes a `() -> number` clock (e.g. `Net.RateLimiter`). |
| `tests/helpers/ObstacleModel.luau` | 2D model of the ball hold against an obstacle box (#97): kinematic character, rolling ball, inelastic contacts, optional face friction. |
| `tests/helpers/FakePlayer.luau` | Player stand-in with `SetAttribute`/`GetAttribute` for attribute specs. |
| `tests/helpers/SourceSection.luau` | Cuts a function out of a Roblox-facing source file for wiring checks. |
| `tests/examples/` | **Examples only.** Fixtures and specs that show the formula, RNG and trade-state-machine patterns. They are not game code and their numbers are not design values. |
| `tests/helpers/Economy.luau` | Binds the pure Formulas, NumberFormat, Rarity and Rng children to the real `Config/*`, like their Roblox `init.luau` files (ADR 0007). |
| `tests/shared/` | Specs for real modules in `src/shared/`: `Formulas/` (concept 7.6, 7.8, 7.9, 8.3, 8.4 tables), `Rng/` (10,000 seeded rolls per table, ±1 pp), `NumberFormat`, `NumberFormatPrice` (#88: prices up, balances down), `Rarity`, `ConfigEconomy`. |
| `tests/client/Ui/` | Pure UI modules (ADR 0008): layout math on real screen sizes (44 px, ⅔, clear zones), window stack, input device, load-status display rule, ball-size field (m/km, "– m", interim MAX! caption). #90: HudScaffold (left-edge buttons for every subset of 0..4, wrapping on small phones, progress bar and zone name, Lobby HUD, pop-up placement clear of joystick, jump and HUD), ZoneProgress (size / zone maximum, zone names, placeholders), ButtonRegistry (hidden until registered, config order), PopupQueue (duration, queue limit). |
| `tests/shared/PopupText`, `tests/shared/Prompts/` | #90 pop-up texts (allowed keys only, K/M numbers, bounds, the `Popup` remote schema) and prompt presets (`Config.Ui.Prompts`: defaults, overrides, loud failures). |
| `tests/server/HudTestService/` | #90 Studio switches: the `HudTestPopup` parser, the Studio-only gate of the switches and placeholder buttons, no client-to-server pop-up path. `tests/places/simulator/server/BallZoneAttribute` checks the `BallZone` player attribute. |
| `tests/server/CurrencyService/` | CurrencyService specs (ADR 0007): balance rules, save edge cases against DataService's `Harness` and fake store, a source scan that no other module writes a balance, and balance attributes on a live server (no Studio) and in Studio. |
| `tests/server/DataService/` | DataService specs (ADR 0006): save rules, session lock between simulated servers, erase, store selection, `DataLoadStatus` on a live server (no Studio) and in Studio. `Harness.luau` builds servers that share one `FakeStore`, with a `FakeClock`, injected JobIds and an optional fault switch (the Studio `DataFailSave`/`DataFailLoad` path). |
| `tests/server/TravelService/` | TravelService specs (ADR 0011): destinations per intent and Place, the 6.5 save/teleport/resume/load-failure cases against a real DataCore, server choice (friend, full, private, reserved), the Studio stub lines (#28 AC1), the travel remotes through the Net guard, and source scans (only PresenceStore names MemoryStoreService, only TravelService names TeleportService, every message key has a text). `TravelHarness.luau` wires TravelCore to DataService's `Harness`, PresenceCore on the fake MemoryStore and a scripted teleporter. |
| `tests/server/PresenceStore/` | Fake MemoryStore (TTL, copies, rejected values, outages, `UpdateAsync`) and PresenceCore (presence, private mapping, untrusted values read back). `ModeCounts` (#37): per-mode player counts over servers, stale servers, size cap, outages. |
| `tests/places/lobby/` | Lobby specs (ADR 0015): `server/` PortalCore (3 s countdown, walking out cancels, closed Multiplayer, 6.5 lock incl. Loading, busy, leave after a travel, the mode in the log), PortalLock (#37 round 1: a rejoin with DataFailLoad on a real DataCore + TravelCore: locked, no travel, no save during Loading and Failed; the Loaded-only gate wiring), FirstJoinArrow (flag set and stored by the first portal travel through a real TravelCore + DataCore, never shown after a rejoin, back after a forced save failure or failed teleport), ChestCore (once per player, members only, double tap, reach, forced save failure, rejoin, crash; against DataCore, CurrencyCore and the fake store), PlayerCounts (refresh ≤ 30 s, every portal of a mode, failed read keeps the value), LobbyMap (ADR 0009 Lobby rules on a fake tree, box push-out, answer cache); `client/` LobbyDisplay (portal boards, countdown seconds, status lines, news countdown, arrow path); `LobbySource` (no remote in Lobby code, portal lock and travel path, chest grant path, Studio gate of every switch). |
| `tests/places/simulator/` | Simulator ball specs (ADR 0002): `server/` BallCore (zone optics, resize steps, leash), GrowthRules (concept 7.4: metres, 40 s calibration on a packet model, speed limit, surfaces, character range, collisions, knock-over), ObstacleRules (contact, new touches, #97 same hit), HitRules (#97: same-hit memory on the run A pattern, rebound watch against the limit, time out vs. time since the touch, round 4: 1.5 s out allowed at a small obstacle), RunAtObstacle (#97 switch value: name, offset, angle) with HitSource (#97 wiring, Studio-only log and `BallRunAtObstacle`), RecoveryRules (#94: put-back candidates on a map-edge, hole and cliff model, obstacle clearance, recovery bound, stuck rule), RecoveryLoop (#94 round 1: same-place loop bound), RecoverySlope (#94 round 2: 25° ramp model, put-back height, stuck reach on slopes, cliff and obstacle still stuck), PlaceBehind (#94 AC8 switch geometry at LargeObstacle) with RecoverySource (log fields, grace, Studio gate, both bounds park, client follows `Recoveries` and `Placements`, slope reach only for stuck, switch Studio-only and no recovery), TrackGrid (own track, regrowth) and CollisionSetup (ADR 0003 rev. 2 table plus the `OtherCharacters` extension of ADR 0002, on a fake PhysicsService); `client/` HoldMath (2D simulation: ball stays in front through every turn, at 60 and 30 fps; after a recovery the hold follows the put-back ball instead of swinging it over the edge; #97: a 46 studs/s rebound stays inside the limit, no overshoot into the character, straight pushing unchanged), HoldObstacle (#97: off-centre push into the LargeObstacle face and walking past the corner within the limit, the AC8 ball behind the obstacle moving less than 2 studs, a pressed ball pushed no harder than HoldMaxAcceleration; on the 2D model `tests/helpers/ObstacleModel.luau`), HoldTurns (#97 R5, round 4: without an obstacle contact every frame of the hold equals main's, small and large ball, 90° and 180° turns, from standing; the arming window, round 5: a `Placements` or `Recoveries` change arms for ReboundWatchTime; `client/fixtures/HoldMathMain.luau` is main's HoldMath at 2746a6d, a test fixture, not game code), HoldSmallObstacle (#97 rounds 4 and 5: a ball touching only a knock-over-able obstacle gets main's hold direction every frame and still arms the brake; d1 the ball gets past the 1-stud cube the character steps over; d2 after the step-over no ball hangs at the cube, while with the contact hold at the cube it does), CameraFit (ball in view at every zone size and screen; #95: exact per-view push distance proven against the frustum planes and silhouette points at 1.6, 26.56 and 50, lower small-ball minimum) and CollisionAssign (plus source scans: no `CanCollide =`, no remote). |
| `tests/places/simulator/` (upgrades) | Upgrade specs (ADR 0010): `server/` UpgradeCore (prices from the formula, level 100 maximum, insufficient coins, invalid id and level, Studio set-level), UpgradeSaveRules (concept 6.5 with the fake store: autosave, restart, forced save failure keeps coins and level together, not loaded, teleport, lost lock), UpgradeAttributes (only `Upgrade<Id>Level` on a live server, source checks of the wiring, MovementService the only `WalkSpeed` writer), StationRules (upgrade stand binding per ADR 0009 on a fake tree); `client/` UpgradesView (rows, before/after, MAX, "–" while not loaded, 44 px row layout). |
| `tests/places/simulator/` (selling) | Selling specs (#38, ADR 0012): `server/` SellCore (coins against the concept formula typed in by hand for all 32 bonus combinations of 8.3 and every factor, worked examples, start size after a sale, before the maximum, Sell value from the next sale, one sale per visit, owner at the ball, refusals, `PetMultiplier` fallback, finds API bounds), SellSaveRules (6.5 with the fake store: autosave, restart, forced save failure, leave failure, not loaded, teleport hand-off, lost lock), SaleOverride (switch text), PlateGeometry (touching and released margins), SellSource (no client-to-server path, `SaleResult` schema, server-only inputs, Studio gate, `ScaleAnchor` only below `Workspace.Map`); `client/` SaleFlight (the label lands on the Coins panel on real screen sizes). |
| `tests/server/TutorialService/`, `tests/client/Ui/Tutorial*`, `tests/shared/ConfigTutorial` | Onboarding specs (#42, ADR 0017): TutorialCore (order, channels, prerequisites, a showing hint keeps its channel, other Places, no profile shows nothing, only known ids set to done and never back, reports only for a showing reportable hint, walked distance without teleports, box distance), TutorialSaveRules (6.5 with the fake store: stored by the next save, rejoin, forced save failure plus rejoin, failed load never resets), TutorialRemote (`TutorialHintDone` through the Net guard: enum, arity, rate), TutorialSource (only TutorialCore writes the fields, Studio gate, guarded remote, HUD untouched); `client/Ui` TutorialGlyphs (device symbols, Upgrades key per device, symbol inside the joystick zone and off the ball on real screen sizes), TutorialPointer (trail and push chevrons); ConfigTutorial (ids consistent, attribute list format). |
| `tests/places/simulator/` (zones) | Zone specs (ADR 0014, #39): `server/` ZoneCore (prices from the formula, cap and map rule, adjacency, double tap, bad zone values, teleport and its wait, start zone, reset), ZoneSaveRules (concept 6.5 with the fake store: immediate save, restart, forced save failure keeps unlock and spend together, crash, double tap, not loaded, lost lock), ZoneAreas (one ZoneStart, boxes, overlap), BallZoneCarry (the ball keeps its metres into the next zone), ZoneSource (remote schema and rate, SaveNow after an unlock, EnterZone, Studio gate, config), ZonePacing (AC6 estimate, pending the real measurement); `client/` ZoneView (window or missing amount, closed barrier, labels, teleport list of only unlocked zones). `tests/shared/ZoneShared` checks `ZonesUnlocked` and the rounded-up missing amount. |
| `tests/places/simulator/` (finds) | Find specs (ADR 0016, #40): `server/` FindCore (only at bound points, 20 s after a point is empty, per player, removed points; values typed in from the concept per rarity and zone; value into SellCore and finds in the ball until the sale; no Legendary in zones 1–5 also when forced; collection first time; Magnet reach from the ball's surface; secret find title and effect; NotHeld / Locked refusals; not loaded), FindRoll (AC7: 10,000 seeded spawns per table within 1 pp, secret 1 in 2,000), FindSaveRules (6.5 with the fake store: next autosave, leave, forced save failure, failed leave save, not loaded, crash, lost lock), FindSource (no client-to-server path, `FindUpdate` schema, server-side pickup inputs, Magnet read every check, ZoneService resolver, Studio gate, single writer of the collection and titles, no tuning literals, catalogue and pop-up texts); `client/` FindView (accepted updates, places and sizes in the ball, rarity colour and symbol, billboards instead of parts). `FindWorld.luau` builds the core on the real config (not a spec). |

Put a spec for `src/<area>/Foo.luau` in `tests/<area>/Foo.spec.luau`.

## Writing a spec

```luau
--!strict
local T = require("../TestKit")
local Places = require("../../src/shared/Config/Places") -- relative to this spec file

return T.suite("Places", function(test)
	test("World 1 is listed", function()
		T.isTrue(Places.Worlds[1] ~= nil)
	end)
end)
```

Paths in `require` are relative to the spec file. A folder with an `init.luau`
is required by its folder name, e.g. `../../src/shared/Config`.

## What can be tested here

Only modules that are pure at require time load under Lune. A module that calls
`game:GetService`, reads Instances or uses Roblox globals such as `Random` when it is
required fails to load. `src/shared/PlaceInfo.luau` is one: it reads Workspace
attributes as soon as it loads. To keep logic testable:

- put formulas, chance tables, state machines and validation in pure modules with no
  service access,
- pass randomness in as a roll or generator argument, so tests use `SeededRandom` and
  live code passes `Random.new()`,
- pass storage in as an interface, so DataService locking can be tested against an
  in-memory fake store,
- keep the Roblox-facing service a thin layer that wires these pieces together.

Seed every random test. A fixed seed makes CI give the same result on every run.

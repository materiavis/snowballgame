# 0002: Snowball push, network ownership, collision groups and zone optics

**Status:** Accepted with merge of PR #89.

First written for the ball prototype (#3, PR #7, never merged on its own). Issue #33 (`7.3-ball-push`) supersedes PR #7: it moves the prototype into the multi-place layout (ADR 0004) and reworks it to concept 7.3 and ADR 0003 rev. 2. This file records the result; the PR #7 version is in that PR's history.

## Context

The game depends on one growing, rolling ball per player staying stable in Roblox physics. Concept 7.3 fixes: the character pushes the ball, the ball sits directly in front of the character in walking direction and rolls along, steering is walking (no ball button, so the touch joystick alone steers), no jumping in the Simulator, the server computes the size, and balls of different players do not collide (✅). Ball physics, animations, camera details and the Visual Cap are Development's call (7.3 Spielraum).

Pure collision pushing (the character walks into the ball) breaks down once the ball is much bigger than the character, and PR #7's force only pushed while the ball was already in front, so after a turn the ball stayed behind. Large parts are also prone to jitter and tunnelling, and ball size is the core progression value, so it must not be decided by the client.

## Decision

**Layout (Simulator only).** `src/places/simulator/server/` holds `BallService` (spawn, ownership, collision groups, size) and `MovementService` (walk speed, no jump). `src/places/simulator/client/` holds `BallController` (hold and roll), `CameraController` (auto zoom), `CollisionController` (local collision groups) and `MovementController` (jump state off). Each keeps its rules in a pure child module tested with `lune run tests`: `BallService/BallCore`, `BallService/CollisionSetup`, `BallController/HoldMath`, `CameraController/CameraFit`, `CollisionController/CollisionAssign`. The Studio switches are in `BallService/StudioSwitches`, part creation and spawn placement (look, material and spawn ray from `Config.Ball`) in `BallService/BallPart`. PR #7's `BallConfig` is merged into `Config/Ball`; zone optics stay in `Config/Zones` and `Formulas.Zones.zoneOptics`. The `SimulatorSkeleton*` placeholders are removed. Lobby and Arena are unchanged and keep Roblox default jumping.

**Holding the ball in front (client).** `BallController` puts a sideways-only `VectorForce` on its own ball and sets it every `PreSimulation`. Gravity and ground friction make the ball roll. The controller works in polar coordinates around the `HumanoidRootPart`:
- the hold direction is the last walking direction (`Humanoid.MoveDirection`), so steering is walking;
- the distance is pulled to `radius + HoldGap`;
- the bearing swings towards the hold direction at a limited angular speed (`HoldTurnRateDegrees`, at most `HoldMaxOrbitSpeedFactor × WalkSpeed` sideways, and never more than `HoldCentripetalShare` of the acceleration limit on the curve). A ball that ends up behind the character therefore travels around it, never through it, and a big ball swings slower;
- the character's velocity is fed forward, so the ball keeps pace and push speed follows `Humanoid.WalkSpeed` (base `Config.Ball.WalkSpeed`; the Walk speed upgrade #36 and the "Schnelle Schuhe" pass #60 only change WalkSpeed later);
- desired speed is capped at `HoldMaxSpeedFactor × WalkSpeed`, acceleration at `HoldMaxAcceleration`; force = acceleration × `AssemblyMass`, so every size responds the same. Without a living character the ball brakes.
- The loop reads cached references and works on numbers; it allocates no tables per frame.

**Network ownership.** `BallService` calls `SetNetworkOwner(player)` on spawn and after every server-side move or resize. The owner simulates the ball, so holding it needs no remote. There is no remote in this feature.

**Server-authoritative size.** The client never sends a size, distance or position. Every `SampleInterval` the server samples each ball:
- distance counts only if both samples were grounded (server ray straight down, length `radius + GroundCheckMargin + radius × GroundCheckMarginPerRadius`, excluding all balls and characters as in PR #7);
- below `MinDistancePerSample` counts nothing; speed counts only up to `MaxCountedSpeed` (20, concept ca. 18–20, from PR #7). Faster movement is counted at that speed (concept 7.3), so upgrades, teleports or an exploiting owner can never grow the ball faster than `MaxCountedSpeed × PrototypeFractionPerStud` per second;
- interim until #34 (7.4): a **size fraction 0..1 within the zone** grows by `counted distance × PrototypeFractionPerStud`. This fraction is the single interface the optics read; #34 replaces only how it grows (metres, start size, 40 s, surfaces, MAX). Ball size is not saved (concept 6.5).
- Start asserts keep `WalkSpeed < MaxCountedSpeed` (base pushing counts fully; replaces PR #7's `PushMaxSpeed < MaxCountedSpeed`), `VisualCap ≤ 2048` and a valid `DefaultZone`.

**Zone optics.** Visual diameter = `zoneOptics(zone) × (OpticsStartFraction + (1 − OpticsStartFraction) × fraction)`, with `zoneOptics(zone) = min(4 + 0.94 × (zone − 1), VisualCap)` studs. Zone 1 goes from 1.6 to 4 studs. The part is the visual ball. It is resized only when the diameter changed by `ResizeStepFraction` of itself (and for the last step at 0 and 1), and only while grounded; the centre moves by the change in radius in the same step so the solver does not push a penetrating ball out. A whole zone takes about 47 resizes over about 42 s instead of one per sample. PR #7's "×N" label is removed; no HUD is built here.

**Current zone.** There is no ZoneService and no zone in the World 1 map yet. `BallService` holds a zone per player, default `Config.Ball.DefaultZone` (1). `BallService.SetZone(player, zone)` (validated with `Formulas.Zones.isZone`) is the hook for ZoneService; `GetZone` and `GetSizeFraction` read it.

**Recovery (does not get stuck).** The server puts the ball back in front of the character on spawn, on every respawn, when it falls below `ResetBelowY`, and when it stays more than `LeashDistance` beyond the hold distance for `LeashTime` seconds (stuck behind an obstacle). The ball's `Recoveries` attribute counts it.

**Collision groups (ADR 0003 rev. 2, extended here).** `BallService` registers four global groups once and applies the table in `Config.Ball.CollisionRules`. The first five rows are the ADR 0003 rev. 2 table. The `OtherCharacters` rows extend it; ADR 0003 itself is unchanged.

| Pair | Collides | Source |
|---|---|---|
| `OwnCharacter` ↔ `OwnBall` | yes | ADR 0003 rev. 2 (pushing) |
| `OwnCharacter` ↔ `Balls` | no | ADR 0003 rev. 2 (walk through foreign balls) |
| `OwnBall` ↔ `Balls` | no | ADR 0003 rev. 2 (concept 7.3 ✅) |
| `Balls` ↔ `Balls` | no | ADR 0003 rev. 2 |
| `OwnCharacter`, `OwnBall`, `Balls` ↔ `Default` | yes | ADR 0003 rev. 2 (world) |
| `OwnBall` ↔ `OtherCharacters` | no | extension: nobody can push or block my ball |
| `OwnCharacter` ↔ `OtherCharacters` | no | extension: nobody can block anyone in the Simulator |
| `Balls` ↔ `OtherCharacters` | no | extension |
| `OtherCharacters` ↔ `OtherCharacters` | no | extension |
| `OtherCharacters` ↔ `Default` | yes | extension (world) |

Why the extension: in the rev. 2 table, foreign characters stay in `Default` on every client. That makes `OwnBall` ↔ `Default` = yes, so another player's character could push or block my ball on my screen. Concept 7.3 ✅ says "Figuren laufen durch fremde Bälle hindurch, niemand kann andere blockieren". The fourth group closes this gap. Development decided this (DM decision in the #33 review, round 1); the concept settles the rule.

Server view (unchanged): every ball is in `Balls`, characters stay in `Default`. Each client's `CollisionController` assigns groups locally from its own view:
- own character parts (including respawns and parts added later) → `OwnCharacter`;
- every part of every other character → `OtherCharacters`. This covers join, respawn, parts added later and parts or models streaming back in; connections are cleaned up on respawn, destroy and leave;
- own ball → `OwnBall`;
- every other ball (also when it streams in again) → `Balls`.

Local `CollisionGroup` changes do not replicate. No part gets `CanCollide = false`, and a source scan in the tests keeps it that way.

**No jumping.** `MovementService` sets `WalkSpeed = Config.Ball.WalkSpeed` and, while `Config.Ball.JumpEnabled` is false, `JumpPower = 0` and `JumpHeight = 0` on every Simulator character; the default touch controls then hide the jump button. `MovementController` turns off the `Jumping` humanoid state on the client, which simulates its own character.

**Camera.** Roblox's third-person camera stays. `CameraController` lifts `Player.CameraMinZoomDistance` to the distance at which the whole ball fits the narrower field of view (vertical, or horizontal on a portrait phone) times `CameraFitMargin`, plus the hold distance for the worst case that the ball is between camera and character. `CameraMaxZoomDistance` rises with it by `CameraMaxZoomExtra`. It runs on ball size, field-of-view and viewport changes only, never per frame. The default camera moves the zoom out when the minimum rises.

## Playtest hooks

- Startup lines:
  - `[BallService] started collisions=ok OwnCharacter<->OwnBall=true OwnCharacter<->Balls=false OwnBall<->Balls=false Balls<->Balls=false OwnCharacter<->Default=true OwnBall<->Default=true Balls<->Default=true OwnBall<->OtherCharacters=false OwnCharacter<->OtherCharacters=false Balls<->OtherCharacters=false OtherCharacters<->OtherCharacters=false OtherCharacters<->Default=true studioSwitches=true`
  - `[CollisionController] started rules=ok …`: the same twelve pairs, read back on the client.
  - `[MovementService] started walkSpeed=16 jumpEnabled=false`, `[BallController] started ownBall=…`, `[CameraController] started minZoom=…`, `[MovementController] started jumpEnabled=false`.
  - `[CollisionController] character <name> parts=N -> OwnCharacter|OtherCharacters`, once per tracked character model.
- Ball part `Workspace.SnowBalls.Ball_<UserId>` attributes (server, replicated): `OwnerUserId`, `Zone`, `SizeFraction` (3 decimals), `VisualDiameter` (studs, equals `Size.X`), `Recoveries`.
- Local player attributes (client view only): `CollisionRulesOk`, `CollisionOwnCharacterParts`, `CollisionForeignCharacterParts` (parts of other characters in `OtherCharacters`), `CollisionOwnBallGroup` (expected `OwnBall`), `CollisionForeignBalls` (balls in `Balls`), `CameraMinZoom`.
- Studio switches on `ServerScriptService`, only in Studio at `game.PlaceId == 0`:
  - `BallTargetUserId` (number): player the switches act on; `0` = every player.
  - `BallSetZone` (number, idle `0`): sets the zone 1..50 and resizes at once; invalid values warn.
  - `BallSetSizeFraction` (number, idle `-1`): sets the fraction 0..1 and resizes at once; invalid values warn.
  - `BallGrowthPaused` (bool): stops growth so a size can be held while walking.
  - `BallRecover` (bool): puts the ball back in front now.
  Each action prints `[BallService] <name> <switch> -> zone=… fraction=… diameter=…`. `BallSetZone = 50` with `BallSetSizeFraction = 1` gives the 50-stud Visual Cap ball for camera and physics checks.

## Consequences

- Server start counts in World 1 grow from 6 to 7 (`BallService`, `MovementService` replace `SimulatorSkeletonService`); client counts from 2 to 5 (`BallController`, `CameraController`, `CollisionController`, `MovementController` replace `SimulatorSkeletonController`). Lobby and Arena are unchanged.
- An exploiting owner can move its own ball and its own character freely (it simulates both, including `WalkSpeed`). It still cannot grow faster than `MaxCountedSpeed × PrototypeFractionPerStud` per second, never while airborne, and cannot send a size. "Growth only while the character is near the ball" (#8) belongs to #34.
- The server writes `Size`/`CFrame` on a client-owned part when it resizes. A short correction may be visible on the owner; check in playtest.
- The ground check is one ray straight down, correct on flat ground. Slopes and ramps need a different check later (kits, #29).
- Characters in the Simulator do not collide with each other either (`OwnCharacter` ↔ `OtherCharacters` = no). Lobby and Arena do not load these modules and keep Roblox defaults.
- Four of the 32 collision groups are used.
- The camera's occlusion handling (Popper) may pull the camera in when the own ball is between camera and character, despite the minimum zoom. Check in playtest.

## Playtest findings (to fill in)

| Question | Result |
|---|---|
| Largest diameter without noticeable jitter / tunnelling (zone 50, 50 studs) | _tbd_ |
| Visual Cap: keep 50 or lower (`Config.Zones.VisualCap`) | _tbd_ |
| Hold feel at 1.6, 4, 20 and 50 studs; `HoldGap` touching visibly | _tbd_ |
| Visible correction when the server resizes a client-owned ball | _tbd_ |
| Camera keeps the 50-stud ball in view in landscape and portrait | _tbd_ |

# 0002: Snowball push, network ownership, collision groups and zone optics

**Status:** Accepted with merge of PR #89.

First written for the ball prototype (#3, PR #7, never merged on its own). Issue #33 (`7.3-ball-push`) supersedes PR #7: it moves the prototype into the multi-place layout (ADR 0004) and reworks it to concept 7.3 and ADR 0003 rev. 2. This file records the result; the PR #7 version is in that PR's history.

## Context

The game depends on one growing, rolling ball per player staying stable in Roblox physics. Concept 7.3 fixes: the character pushes the ball, the ball sits directly in front of the character in walking direction and rolls along, steering is walking (no ball button, so the touch joystick alone steers), no jumping in the Simulator, the server computes the size, and balls of different players do not collide (✅). Ball physics, animations, camera details and the Visual Cap are Development's call (7.3 Spielraum).

Pure collision pushing (the character walks into the ball) breaks down once the ball is much bigger than the character, and PR #7's force only pushed while the ball was already in front, so after a turn the ball stayed behind. Large parts are also prone to jitter and tunnelling, and ball size is the core progression value, so it must not be decided by the client.

## Decision

**Layout (Simulator only).** `src/places/simulator/server/` holds `BallService` (spawn, ownership, collision groups, size) and `MovementService` (walk speed, no jump). `src/places/simulator/client/` holds `BallController` (hold and roll), `CameraController` (auto zoom, push past the own ball), `CollisionController` (local collision groups) and `MovementController` (jump state off). Each keeps its rules in a pure child module tested with `lune run tests`: `BallService/BallCore`, `BallService/CollisionSetup`, `BallController/HoldMath`, `CameraController/CameraFit`, `CollisionController/CollisionAssign`. The Studio switches are in `BallService/StudioSwitches`, part creation and spawn placement (look, material and spawn ray from `Config.Ball`) in `BallService/BallPart`. PR #7's `BallConfig` is merged into `Config/Ball`; zone optics stay in `Config/Zones` and `Formulas.Zones.zoneOptics`. The `SimulatorSkeleton*` placeholders are removed. Lobby and Arena are unchanged and keep Roblox default jumping.

**Holding the ball in front (client).** `BallController` puts a sideways-only `VectorForce` on its own ball and sets it every `PreSimulation`. Gravity and ground friction make the ball roll. The controller works in polar coordinates around the `HumanoidRootPart`:
- the hold direction is the last walking direction (`Humanoid.MoveDirection`), so steering is walking;
- the distance is pulled to `radius + HoldGap`;
- the bearing swings towards the hold direction at a limited angular speed (`HoldTurnRateDegrees`, at most `HoldMaxOrbitSpeedFactor × WalkSpeed` sideways, and never more than `HoldCentripetalShare` of the acceleration limit on the curve). A ball that ends up behind the character therefore travels around it, never through it, and a big ball swings slower;
- the character's velocity is fed forward, so the ball keeps pace and push speed follows `Humanoid.WalkSpeed` (base `Config.Ball.WalkSpeed`; the Walk speed upgrade #36 and the "Schnelle Schuhe" pass #60 only change WalkSpeed later);
- desired speed is capped at `HoldMaxSpeedFactor × WalkSpeed`, acceleration at `HoldMaxAcceleration`; force = acceleration × `AssemblyMass`, so every size responds the same. Without a living character the ball brakes.
- The loop reads cached references and works on numbers; it allocates no tables per frame.

**Network ownership.** `BallService` calls `SetNetworkOwner(player)` on spawn and after every server-side move or resize. The owner simulates the ball, so holding it needs no remote. There is no remote in this feature.

**Server-authoritative size.** The client never sends a size, distance or position. Every `SampleInterval` the server samples each ball and grows a **size fraction 0..1 within the zone**, the single interface the optics read. How it grows is in "Growth" below. Ball size is not saved (concept 6.5). Start asserts keep `WalkSpeed < MaxCountedSpeed` (base pushing counts fully; replaces PR #7's `PushMaxSpeed < MaxCountedSpeed`), `GrowthRange > HoldGap`, `VisualCap ≤ 2048` and a valid `DefaultZone`.

**Zone optics.** Visual diameter = `zoneOptics(zone) × (OpticsStartFraction + (1 − OpticsStartFraction) × fraction)`, with `zoneOptics(zone) = min(4 + 0.94 × (zone − 1), VisualCap)` studs. Zone 1 goes from 1.6 to 4 studs. The part is the visual ball. It is resized only when the diameter changed by `ResizeStepFraction` of itself (and for the last step at 0 and 1), and only while grounded; the centre moves by the change in radius in the same step so the solver does not push a penetrating ball out. A whole zone takes about 47 resizes over about 40 s instead of one per sample. PR #7's "×N" label is removed.

**Current zone.** There is no ZoneService and no zone in the World 1 map yet. `BallService` holds a zone per player, default `Config.Ball.DefaultZone` (1). `BallService.SetZone(player, zone)` (validated with `Formulas.Zones.isZone`) is the hook for ZoneService; `GetZone`, `GetSizeFraction` and `GetSizeMetres` read it.

## Growth (issue #34, concept 7.4)

Modules: `BallService/GrowthRules` (pure: metres, credit, block reasons, collision, knock-over), `BallService/ObstacleRules` (pure: contact distance, what a touch means), `BallService/GrowthModifiers` (the upgrade seam), `BallService/BallStep` (one sample of one ball), `BallService/Obstacles` (tagged obstacles, knock-over), `BallService/BallAttributes` (published size), `SurfaceService` (tag lookup) with its pure `TrackGrid`, and the client `BallGrowthController`. There is still no remote.

**Size.** Fraction 0 is the start size (`StartSizeFraction`, 10 % of `Formulas.Zones.maxSize(zone)`), fraction 1 the maximum, metres are linear between them. The optics keep reading the fraction, so the visual cap (`VisualCap`) and metres diverge on purpose.

**Growth rate.** A full zone is `timeToMax × WalkSpeed` studs of normal snow (640 at level 0), so `fractionPerStud = 1 / (timeToMax × WalkSpeed)` (Q-G, ADR 0003). Growth is proportional to counted speed up to `MaxCountedSpeed`. Deep snow multiplies by `DeepSnowGrowthMultiplier`.

**Calibration (AC1).** The interim growth, configured for 41.7 s, measured 47.1 s by hand and 47.4 s by the playtester, which is 14.1 studs/s counted against 16 walked. Nothing in the server maths loses 12 %: `MinDistancePerSample` (0.05) is far below a sample (1.6), and the ground ray does not fail on flat ground. The likely cause is the per-sample limit `min(distance, MaxCountedSpeed × elapsed)`. The position of a client-owned ball reaches the server in packets, not continuously. A sample that saw no new packet counts nothing and the next one sees two packets' worth, which the limit (2 studs per 0.1 s) cuts off; each server resize (47 per zone) adds a short stall that feeds the same loss. A headless model of this reproduces the measurement: 20 packets/s with ±20–40 ms jitter and a 0.15 s stall per resize gives 46.5 to 48.4 s for the old rule against 41.7 s ideal. **This is a model that matches the two measurements, not a proof: Studio was not available to this change.** Replacing the limit per sample by a credit removes the cause: `CountedBurstWindow` (0.5 s) of `MaxCountedSpeed` is refilled over time and spent by counted distance, so bursts count in full and the long-run limit stays `MaxCountedSpeed`, however the owner times its packets. `GrowthRules.spec` runs the same packet model. `MeasuredTimeToMax`, `RolledStuds`, `CountedStuds` and `GrowthSeconds` tell in a playtest whether a remaining deviation is the count or the ball's real speed. A real ball speed of 16 studs/s is assumed. Below 14.9 studs/s AC1 would fail (640 studs in more than 43 s), and the fix would be a calibrated reference speed instead of `WalkSpeed`. `GrowthCounts` flickers to false on samples that saw no new packet (`NotRolling`); that distance is counted by the next sample.

**What counts.** A sample grows the ball only if, in this order (the first failure is published as `GrowthBlock`): not `Paused`, not `AtMax`, a living character exists (`NoCharacter`), the character is in range (`TooFar`), both samples grounded (`Airborne`), the surface is snow (`NoSnow`), not on the own track (`Track`), and the ball moved at least `MinDistancePerSample` horizontally (`NotRolling`). Distance is horizontal: a resize moves the centre vertically, and that is not rolling.

**Character range (AC4).** The root part must be within `GrowthRange` (6 studs) of the ball's **edge on the ground plane** and within `GrowthVerticalRange` of the ball's top or bottom. The true distance to the sphere grows with the radius for a character standing beside it (at the 50-stud ball about 9.4 studs at the hold distance), so no single number would work; the distance to the edge on the ground plane is `HoldGap` at every size. 6 studs is 4× `HoldGap`: room for turning and for character and ball arriving in separate packets, while walking away leaves it in well under a second. Nothing asks whether the character moves, so a ball coasting after a push grows while the character stays in range.

**Surfaces (ADR 0003 D3).** One ray straight down from the ball's centre; `SurfaceService.classify` takes the first tag in `SurfacePriority` on the hit part (`Snow`, `DeepSnow`, `Ice`, `Grass`). Ice, Grass and untagged ground give no growth. Tags are on BaseParts, so a patch may be a non-colliding part lying on the ground (`RespectCanCollide` is false on the ground ray), which keeps the physics flat.

**Track.** Per player, logical, on the server, and never touches geometry (`TrackGrid`). Cell size `TrackCellSize` (4 studs). A cell becomes track when the contact point **has left** it, so the cell under the ball is never its own track and walking straight is fresh snow all the way. `TrackCellHysteresis` (0.5) keeps a walk along a cell border from flipping between two cells: spawn is at x = 0, exactly a border. Track expires `TrackRegrowTime` after the cell was last rolled. Only the contact line is track: a ball touches the ground at one point, and marking the width of a 50-stud ball would mark the snow in front of it and stop its growth, so a huge ball can avoid its own track by moving a few studs sideways. `TrackMaxRolledPerCell` (8) stops rolling back and forth inside one cell from growing forever. How the track looks is not built (7.4 Spielraum), and nothing is rendered per player.

**Obstacles.** Tagged `Obstacle`, BaseParts. The server measures contact from the replicated ball position (`GetPartBoundsInRadius`, then the exact distance to the box), because `Touched` on a client-owned part is reported by that client. Contact margin `CollisionContactMargin` (0.25). A new touch is one collision, and pressing against the same tree is not a steady drain; the first sample after the ball was placed only records contact. A collision costs `size × (1 − loss)` of the current metres, never below the start size, then `CollisionProtection` (1 s). A resize that follows uses the normal step.

**Knock-over.** An obstacle with the number attribute `KnockOverSize` (studs) is knocked over without loss when the ball's visual diameter is at least `KnockOverSizeRatio` (3) times that size. Studs against studs, because metres and studs diverge under the visual cap. It is taken out of the world for everyone and returns after `KnockOverRespawn` (30 s), or `KnockOverRetryInterval` later while a ball is where it would return. An obstacle without the attribute (or with nonsense) is never knocked over.

**Upgrades.** `GrowthModifiers` is the one seam. It reads `Formulas.Upgrades.effect` with level 0 from `Config/Upgrades` (`growth.Start` 40 s, `stability.Start` 10 %) until UpgradeService calls `setLevelSource`. `Config.Ball.TimeToMax` and `CollisionSizeLoss` are removed, because they would be a second source of truth. Level 100 is 8 s and 2 %.

**MAX and the size display.** Published attributes on the Player: `BallSizeMetres`, `BallSizeFraction`, `BallIsMax`, and `BallScaleAnchor` (Vector3 of the nearest `ScaleAnchor`-tagged instance, set when the ball reaches MAX, because the anchor itself may be streamed out on the client). On the ball: `SizeMetres`, `IsMax`. Attributes are written at most every `PublishInterval` (0.25 s) or on a change of the MAX state or a resize. `BallGrowthController` builds everything for the local player only (ADR 0003 R2): a top-centre size label with `NumberFormat.size`, "MAX!", a glow (`PointLight`, `Highlight`) on the own ball, and an arrow from two handle adornments (no asset, no physics). Foreign balls get nothing. `Config.Ball.MaxSoundId` is empty, so no sound plays yet.

**Assumptions (concept is silent).** Size loss never goes below the start size (DM). A knock-over is global, not per player (7.4 names per-player rules only for the track). Pressing against one obstacle is one collision. Obstacles are box-shaped for the contact test, so a tagged cylinder or sphere counts by its box.

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

**Camera.** Roblox's third-person camera stays. `CameraController` does two things.

*Fit.* It lifts `Player.CameraMinZoomDistance` to the distance at which the whole ball fits. The camera aims at the character, not at the ball, so the ball is off-axis. `CameraFit.ballReach` is the distance from the camera focus to the farthest point of a ball resting on the ground, `holdDistance` away on any bearing, for a focus between `CameraFocusHeightMin` and `CameraFocusHeightMax` above the ground. The zoom is that reach / sin(narrower half field of view) × `CameraFitMargin` (vertical, or horizontal on a portrait phone). This holds for every ball bearing and camera pitch. The focus height is a range because a big ball's centre is above the focus and a small ball's far below it; using only `radius` for the height difference would be too short for small balls. `CameraFitMargin` is 1.1 (was 1.25 on the old on-axis formula): the bound is already tight for the worst pitch, and more margin only makes the ball smaller on screen. `CameraMaxZoomDistance` rises by `CameraMaxZoomExtra` only if the requirement goes above Roblox's default maximum of 400. At diameter 50 the minimum is 114.0 studs at 16:9 and 212.6 at 9:19.5, so the maximum stays 400. This part runs on ball size, field-of-view and viewport changes only.

*Occlusion.* Roblox's default "Zoom" occlusion (Poppercam) treats the opaque, collidable own ball as an occluder and pulls the camera in front of it, ignoring the zoom minimum. The ball must stay opaque and collidable, so the occluder rules cannot be escaped by changing the part. One render step directly after `Enum.RenderPriority.Camera` pushes the camera back along its look direction to the required distance while it is closer to its focus than that. To keep real walls working, one raycast from the focus towards the wanted camera position limits the push (`CameraWallClearance` before the wall). It excludes the ball folder and all characters: the own ball is what the push looks past, and foreign balls and characters cannot block anyone (concept 7.3 ✅). The step does nothing without a ball or within `CameraPushTolerance` of the required distance, reuses one `RaycastParams` whose filter is updated on player and character events, and allocates no tables per frame. The decision itself is the pure `CameraFit.needsPush` and `CameraFit.pushedDistance`. Invisicam was rejected because it fades the ball itself and also world objects, and the ball has to stay visible.

*After the ball shrinks (owner decision, Marco, 2026-11-09).* Only the minimum drops back. There is no automatic zoom back: the camera may stay far away as long as the player can zoom in with the mouse wheel.

## Playtest hooks

- Startup lines:
  - `[BallService] started collisions=ok OwnCharacter<->OwnBall=true OwnCharacter<->Balls=false OwnBall<->Balls=false Balls<->Balls=false OwnCharacter<->Default=true OwnBall<->Default=true Balls<->Default=true OwnBall<->OtherCharacters=false OwnCharacter<->OtherCharacters=false Balls<->OtherCharacters=false OtherCharacters<->OtherCharacters=false OtherCharacters<->Default=true studioSwitches=true`
  - `[CollisionController] started rules=ok …`: the same twelve pairs, read back on the client.
  - `[MovementService] started walkSpeed=16 jumpEnabled=false`, `[BallController] started ownBall=…`, `[CameraController] started minZoom=…`, `[MovementController] started jumpEnabled=false`.
  - `[CollisionController] character <name> parts=N -> OwnCharacter|OtherCharacters`, once per tracked character model.
  - `[SurfaceService] started DeepSnow=N Snow=N Ice=N Grass=N` and `[BallGrowthController] started ownBall=…`.
- Ball part `Workspace.SnowBalls.Ball_<UserId>` attributes (server, replicated): `OwnerUserId`, `Zone`, `SizeFraction` (3 decimals), `VisualDiameter` (studs, equals `Size.X`), `Recoveries`, `SizeMetres`, `IsMax`. Only in Studio at PlaceId 0, also: `Surface` (`Snow`, `DeepSnow`, `Ice`, `Grass`, `None`, `Air`), `GrowthCounts`, `GrowthBlock` (empty while growing, otherwise the reason), `LastCollisionLoss` (metres, 0 = the last collision was protected), `Collisions`, `KnockOvers`, `TrackCells`, `RolledStuds`, `CountedStuds`, `GrowthSeconds`, `MeasuredTimeToMax` (seconds from the first growth to the maximum; reset by `BallSetSizeFraction`).
- Player attributes (server, replicated): `BallSizeMetres`, `BallSizeFraction`, `BallIsMax`, `BallScaleAnchor`.
- A knocked-over obstacle is missing from `Workspace.Map.Placeholder` and prints `[BallService] obstacle <name> knocked over` and `… is back`.
- Placeholder fixtures in `world/world1/Placeholder.rbxmx` (the ground is `Snow`): `DeepSnowPatch` (x 30..60, z 50..-350, long enough for a 20 s straight run), `IcePatch` and `GrassPatch` (x -60..-30), `LargeObstacle` (8 studs, x 20, z -30, no `KnockOverSize`), `SmallObstacle` (1 stud, x -20, z -30, `KnockOverSize` 1, so a ball from 3 studs, zone 1 fraction ≥ 0.59, knocks it over), `ScaleAnchorPlaceholder` (z 60). The straight line along -Z from the spawn (at least 640 studs) stays clear for the 40 s run.
- Local player attributes (client view only): `CollisionRulesOk`, `CollisionOwnCharacterParts`, `CollisionForeignCharacterParts` (parts of other characters in `OtherCharacters`), `CollisionOwnBallGroup` (expected `OwnBall`), `CollisionForeignBalls` (balls in `Balls`), `CameraMinZoom`.
- Studio switches on `ServerScriptService`, only in Studio at `game.PlaceId == 0`:
  - `BallTargetUserId` (number): player the switches act on; `0` = every player.
  - `BallSetZone` (number, idle `0`): sets the zone 1..50 and resizes at once; invalid values warn.
  - `BallSetSizeFraction` (number, idle `-1`): sets the fraction 0..1 and resizes at once; invalid values warn.
  - `BallGrowthPaused` (bool): stops growth so a size can be held while walking.
  - `BallRecover` (bool): puts the ball back in front now.
  - `BallSimulateCollision` (bool): one collision now, respecting the protection time. Set it twice within 1 s to test AC3.
  - `BallMoveCharacterAway` (number, idle `0`): moves the character this many studs away from the ball. The hold keeps the ball with the character, so a plain walk never leaves the range; after this switch the ball chases the character over the snow while out of range (`GrowthBlock = TooFar`).
  - `BallClearTrack` (bool): forgets the target's track.
  Each action prints `[BallService] <name> <switch> -> zone=… fraction=… diameter=… metres=…`. `BallSetZone = 50` with `BallSetSizeFraction = 1` gives the 50-stud Visual Cap ball for camera and physics checks.

## Consequences

- Server start counts in World 1 grow from 6 to 8 (`BallService`, `MovementService` and `SurfaceService` replace `SimulatorSkeletonService`); client counts from 2 to 6 (`BallController`, `BallGrowthController`, `CameraController`, `CollisionController`, `MovementController` replace `SimulatorSkeletonController`). Lobby and Arena are unchanged and do not load these modules.
- An exploiting owner can move its own ball and its own character freely (it simulates both, including `WalkSpeed`). It still cannot grow faster than `MaxCountedSpeed × fractionPerStud` per second over time, never while airborne or away from snow, and cannot send a size.
- The server writes `Size`/`CFrame` on a client-owned part when it resizes. A short correction may be visible on the owner; check in playtest.
- The ground check is one ray straight down, correct on flat ground. Slopes and ramps need a different check later (kits, #29).
- Characters in the Simulator do not collide with each other either (`OwnCharacter` ↔ `OtherCharacters` = no). Lobby and Arena do not load these modules and keep Roblox defaults.
- Four of the 32 collision groups are used.
- The default occlusion still pulls the camera in for the own ball; the render step then pushes it back in the same frame (see Camera). If the player had zoomed out farther than the minimum, the camera returns only to the minimum while the ball is in the way, because the player's zoom target is private to the default camera.
- When a wall or the ground limits the camera, the push stops before it and the ball may not fit fully. That is deliberate: the camera must not end up behind a wall. Looking up from low down with a big ball is the common case, because the camera then sits at the ground. Every queryable part counts as a wall for the push, including invisible and non-collidable ones (`CanQuery` off excludes a part). The default occlusion ignores non-collidable parts, so a later map with large trigger volumes or decoration between camera and character needs them set to `CanQuery` off.
- The zoom bound assumes the ball rests on the ground at its hold distance. A ball stuck behind an obstacle can be up to `LeashDistance` farther away until the recovery brings it back; only the margin covers that.
- The minimum zoom also applies to small balls: in zone 1 it is about 12.4 studs in landscape and 23.2 in portrait at fraction 0, because the ball lies well below the focus.

## Playtest results at 880f5a0

Sources: the playtester report and the hand playtest by Marco on PR #89, both for `880f5a06f57ba6a2b2fe8bb682a538d09cc55b0a`, World 1. Both reports were FAIL on AC3. Results of retests of later commits are recorded as PR #89 comments, not in this file.

| Question | Result at 880f5a0 |
|---|---|
| Camera, 50-stud ball between camera and character | FAIL (hand run): the camera jumps close to the character and the ball leaves the view. Fixed in this round (occlusion push, see Camera). |
| Camera, 50-stud ball off-axis | FAIL (playtester): top of the ball cut off at `CameraMinZoom` 80.98, camera distance 81.4, pitch −15°, FOV 70, viewport 774×311. Hand run: fully in view with the ball beside the character, almost no top margin. Fixed in this round (new fit, see Camera). |
| Camera, 50-stud ball in front of the character | PASS (hand run): whole ball in view. |
| Camera in portrait | Not assessed at 880f5a0. |
| Camera after the ball shrinks | `CameraMinZoom` back to 4.1, the camera distance stays at 81.4 and the mouse wheel zooms in. Accepted by owner decision (see Camera). |
| Turn with the small ball | Looks good by eye (hand run, W/A/S); time not measured. |
| Turn 180° at 50 studs | Swings outside around the character and is in walking direction after about 3 s (hand run). |
| Ball position after turns (playtester) | No keyboard input; with navigation only, the ball was back beside or in front of the character, more to the side than in front, never in the character. Time not measured. |
| Growth, zone 1, fraction 0 to 1 | 47.1 s with the key held throughout (hand run, single measurement), against the expected 42 s ±5 (37–47 s), so 0.1 s above the range. Not tuned (owner decision, Marco, 2026-11-09); the interim growth is replaced in #34. Config maths give 1 / 0.0015 / 16 ≈ 41.7 s. The playtester's ~37 s estimate from partial distances is superseded. `Config.Ball.TimeToMax = 40` is not used by the interim growth; it belongs to #34. Standing still: no growth (playtester). |
| No jumping | PASS: Space leaves the character on the ground (hand run); `JumpPower`, `JumpHeight` 0 and `Jumping` state off (playtester). |
| Startup lines, groups, attributes, invalid Studio switches | PASS (playtester). No script errors in the playtester console; the hand-run output was not fully reviewed. |
| Recovery when stuck | Only `BallRecover=true` (`Recoveries` 0→1, ball back after 1.5 s). The real stuck and leash path is not assessed at 880f5a0: the placeholder map has no obstacle. |
| Largest diameter without noticeable jitter / tunnelling (zone 50, 50 studs) | Not assessed at 880f5a0. |
| Visual Cap (`Config.Zones.VisualCap`) | Stays 50, unchanged. Not assessed at 880f5a0. |
| Hold feel at 20 studs; `HoldGap` touching visibly | Not assessed at 880f5a0. |
| Visible correction when the server resizes a client-owned ball | Not assessed at 880f5a0. |
| Lobby and Arena (runs B, C), two players (run D), phone (Jan, #4) | Not run at 880f5a0. |

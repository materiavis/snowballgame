# 0002 — Snowball push model, network ownership, collision groups and visual size cap

**Status:** Proposed (prototype for #3, stable size limit still to be measured in playtest)

## Context
The whole game depends on one growing, rolling ball per player staying stable in Roblox physics.
Pure collision pushing (character walks into the ball) breaks down once the ball is much bigger and heavier
than the character, and very large parts are prone to jitter and tunnelling. Ball size is also the core
progression value, so it must not be decided by the client.

## Decision

**Push model (scripted push).** The client (`BallController`) puts a `VectorForce` on its own ball and sets it
every `PreSimulation` step:
- The character pushes while it is within contact range and moving towards the ball. Contact range is the gap
  between the `HumanoidRootPart` and the ball *surface* (`distance to center - radius`), limited by
  `ContactRangeBase + radius * ContactRangePerRadius`. Against a large sphere the character's head touches first
  and this gap levels out around 2 studs, so the same check works for small and very large balls.
- Force = move direction × `PushAcceleration` × ball mass, so a large ball accelerates like a small one.
  No force is added above `PushMaxSpeed`, which is below the walk speed, so the character stays at the surface.
- While pushing, sideways velocity is damped (`PushSteerGain`) so the ball follows the move direction.
- When nobody pushes, a braking force (`BrakeAcceleration`) slows the ball, since Roblox has no rolling resistance.
- The character still collides with balls normally; collision only keeps the character at the surface, it does
  not move the ball in any meaningful way.

**Network ownership.** `BallService` calls `SetNetworkOwner(player)` on spawn and after every server-side move
or resize. The owning client simulates the ball, so pushing is lag-free and needs no RemoteEvent.
Only the owner's local `VectorForce` acts on the ball.

**Server-authoritative growth.** `BallService` samples every ball every `SampleInterval`:
- distance between samples counts only if both samples were grounded (server raycast straight down,
  length `radius + GroundCheckMargin + radius * GroundCheckMarginPerRadius`, excluding balls and characters),
- movement below `MinDistancePerSample` (standing still / jitter) and above `MaxCountedSpeed` is ignored,
- internal diameter grows by `distance * GrowthPerStud`,
- the part is resized only once the pending growth reaches `GrowthStep`, and only while grounded; the center is
  raised by the added radius in the same step so the ball does not get pushed out of the ground by the solver.

**Collision groups.** All balls are in the `SnowBalls` collision group, which does not collide with itself.
Characters and the world still collide with every ball.

**Visual size cap.** Physical diameter = `min(internalSize, VisualCapDiameter)`. Past the cap the part stops
changing, the internal size keeps growing and is published as the `InternalSize` attribute; clients show
`×N` with `N = internalSize / VisualCapDiameter`.

## Consequences
- An exploiting owner can move its own ball freely (it simulates it). This cannot inflate size faster than
  `MaxCountedSpeed × GrowthPerStud` per second and never while airborne; it can still "roll" a ball without
  pushing it. Acceptable for a prototype; revisit if size becomes valuable (e.g. require the character near the
  ball for distance to count).
- The server writes `Size`/`CFrame` on a client-owned part when growing. Changes replicate together, but a
  short correction may be visible on the owner; check in playtest.
- The ground check is a single ray straight down, which is correct on flat ground only. Slopes and ramps need a
  different check (e.g. spherecast or contact-based) later.
- Ball-vs-ball bumping is impossible until the collision group rule is revisited.

## Playtest findings (to fill in)
| Question | Result |
|---|---|
| Largest diameter without noticeable jitter / tunnelling | _tbd_ |
| Recommended `VisualCapDiameter` | _tbd_ (placeholder 50) |
| Push feel at small / medium / capped size | _tbd_ |
| Visible correction when the server resizes a client-owned ball | _tbd_ |

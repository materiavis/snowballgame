# 0004: Multi-Place Rojo setup

**Status:** Proposed in the PR for #23; humans decide by reviewing it, because it changes repository rules.

Implements the "Places, Rojo and world assets" section of [ADR 0003](0003-snow-rush-intake.md) and records what that section left open.

## Context

ADR 0003 gives each Place its own Rojo project and leaves two things to this PR: what happens to `default.project.json` (D2), and the details of the loaders. The project files also have to coexist with a shared `Config` module and a `Config/*` folder.

## Decision

- **`default.project.json` stays as an alias of World 1.** Its tree is only `{"$path": "places/world1.project.json"}`, so there is no second mapping that can drift. Plain `rojo build` and `rojo serve` still produce a valid Place, which matters because `.claude/**` still uses them. The explicit per-Place commands are the documented rule.
- **`Config` becomes a folder module.** `src/shared/Config/init.luau` keeps the contents and require path of the old `Config.luau`; `Config/Places` sits below it. A `Config.luau` next to a `Config/` folder would make two children with the same name.
- **`PlaceInfo` is the only reader of `PlaceRole` and `WorldIndex`, and errors instead of defaulting.** A Place built from the wrong project stops at startup rather than running the wrong services. On the client it waits for `game.Loaded` before reading, because the attributes arrive through replication.
- **Loaders wait for folders by role, never with `FindFirstChild`.** Every project mounts `PlaceServices`/`PlaceControllers`, and only the roles marked in `PlaceInfo` mount the Social folders. An unmounted folder that a role expects shows up as an infinite-yield warning, not as a silent skip.
- **World 1 has one `Placeholder.rbxmx` area and no zones yet.** Its ground is 2048 x 2048 studs, the Roblox part limit. The prototype ball reaches its visual cap after about 920 studs of rolling, so a smaller ground would not allow testing the cap from the spawn point.
- **`world/kits` is not mapped yet.** `ServerStorage.Kit` arrives with the kit content (#29), so that no project mounts a file that does not exist.

## Consequences

- A new world needs a `places/worldN.project.json` and a `Config/Places.Worlds[N]` entry. CI picks up the project by itself.
- Only the alias build depends on World 1 being the default. Moving the default later means changing one line.
- The Lobby and Arena Places have no ground until their areas exist, so characters fall and respawn there. This produces no script errors and does not affect the startup check.
- Skeleton modules (`*SkeletonService`, `*SkeletonController`) exist only so that each folder's startup is observable. Features delete them when a real module arrives.
- Studio behaviour of the `game.Loaded` wait and the role-based folder waits is unverified until the playtest. The expected server and client start counts are 2 in Lobby and World 1, and 1 in Arena.

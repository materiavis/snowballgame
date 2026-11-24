# World builder

General tools to build zones (map areas) for any game. Used by the `world-builder` agent
(`.claude/agents/world-builder.md`). Nothing in this folder knows a game: the game's own names
come from its world rules, `src/shared/Config/WorldRules.luau`.

## Files

| File | What it does |
|---|---|
| `build.luau` | The command: `lune run tools/world/build <world> [zone]`. Builds zones from plans. |
| `Builder.luau` | Reads plans and the kit, places the objects, writes zone files and fingerprints. |
| `ZoneContract.luau` | The zone check. Says what is wrong with a zone file, by the world rules. |
| `templates/Zone.plan.json` | Starting point for a new plan. |
| `<world>/ZoneNN.plan.json` | One plan per zone (written by the agent). |
| `<world>/fingerprints.json` | Fingerprint of every zone file the builder wrote. |

Tests: `tests/world/ZoneContract.spec.luau` (the check, with invented rules, plus every real
zone file) and `tests/world/WorldBuilder.spec.luau` (the builder, with an invented kit).

## Flow

```txt
issue (world-task) -> plan per zone -> lune run tools/world/build <world>
                                         |-- reads the kit
                                         |-- builds each zone in memory
                                         |-- zone check
                                         '-- writes world/<world>/ZoneNN.rbxmx only if every zone passes
```

If one plan has a mistake or one zone fails the check, nothing is written.
A zone file whose fingerprint differs from the last build was changed by hand (in Studio). The
builder never overwrites it and reports `changed by hand`. To let the builder take it over again,
a person deletes the zone file or its entry in `fingerprints.json`.

## Plan

`tools/world/<world>/ZoneNN.plan.json`. Positions and sizes in studs, `[x, y, z]`; y is up.

| Field | Meaning |
|---|---|
| `zone` | Zone number, the same as NN in the file name. |
| `kit` | Path of the kit from the repository root, e.g. `world/kits/<kit>.rbxmx`. |
| `ground` | List of ground blocks: `name`, `size`, `position` (middle of the block), optional `material` (Roblox material name), `color` (`[r, g, b]`, 0–255) and `tags`. |
| `start` | Where players arrive. The builder puts a small invisible part there with the start tag from the world rules. |
| `bounds` | Invisible walls around the rectangle `min` `[x, z]` to `max` `[x, z]`, from `bottom` (default 0) up to `bottom + height`. |
| `objects` | List of placed templates: `template` (name in the kit), `position` (where the middle of the underside of the template's base goes), optional `rotation` (degrees around the vertical axis), `scale` and `name`. |

## Kit

`world/kits/<kit>.rbxmx` holds one Folder. Every Model directly in it is a template:

- `PrimaryPart` is the template's base. It decides where the object stands.
- Tags and attributes the game needs are already on the template (the world rules say which
  tag goes on which kind of object).
- `ScaleMin` and `ScaleMax` (number attributes) allow scaling in a plan. Without them only scale 1
  is allowed.

## Zone check

Checks every `world/<world>/ZoneNN.rbxmx`:

1. The zone root is a Folder (or a Model that does not stream as one block) and has its zone
   number as an attribute, matching the file name. No other object carries the zone number.
2. Exactly one start.
3. Every tag sits on the kind of object the world rules ask for: `Point` (Attachment or BasePart),
   `Part` (BasePart) or `Group` (Model with a PrimaryPart and the streaming mode from the rules).
4. Attributes the rules list as positive are positive numbers.
5. A folder with invisible, colliding, anchored walls.
6. Optional: how many objects carry a tag (a Model counts once), and what share of them carries
   an attribute. The limits are in the world rules, per world under `Worlds`.
7. No zone number is used twice in a world.

## For another game

Copy `tools/world/`, `tests/world/` and `.claude/agents/world-builder.md`, then write the game's
own `src/shared/Config/WorldRules.luau`. Nothing else has to change.

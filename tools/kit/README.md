# Building kits

Building kits are made by the `asset-builder` agent (`.claude/agents/asset-builder.md`) and used
by the `world-builder` (`tools/world/`). Nothing in this folder knows a game: the game's own names
come from its world rules, `src/shared/Config/WorldRules.luau`. The kit format itself is in
`tools/world/README.md`, section "Kit".

## Files

| File | What it is |
|---|---|
| `KitContract.luau` | The kit check. Says what is wrong with a kit file, by the world rules and the upload list. |
| `<kit>/` | One folder per kit: the generator, `check.py`, the Lune script that writes the kit file. |
| `<kit>/parts.json` | Every template: part, variant, seed, size, triangle count. |
| `<kit>/upload-list.json` | Asset IDs a human uploaded (see below). |
| `world/kits/<kit>.rbxmx` | The kit file, written by the Lune script. |

`.glb` exports, previews and the gallery are binary files and live in Materiavis Files under
`AI-Output/kits/<kit>/`, never in this repository.

Test: `tests/kit/KitContract.spec.luau` (the check with invented rules, a kit-to-zone round trip
through the world-builder, plus every real kit in `world/kits/`).

## Flow

```txt
issue (asset task) -> generator -> .glb + gallery in Files -> PR (round 1)
                   -> human uploads in Studio (group Materiavis), fills upload-list.json
                   -> Lune script writes world/kits/<kit>.rbxmx -> kit check -> PR (round 2)
```

## Upload list

`tools/kit/<kit>/upload-list.json`. Only a human writes it, after uploading the mesh in Roblox
Studio under the group Materiavis. One entry per uploaded mesh, keyed by template name:

```json
{
  "Rock_1": { "meshId": 1234567890, "textureId": 1234567891 },
  "Rock_2": { "meshId": 1234567892, "textureId": null }
}
```

IDs are numbers, not `rbxassetid://` strings. The kit check fails on any MeshId or TextureID in a
kit that is not in this list.

## What the kit check checks

1. The kit root is a Folder with at least one template, and only templates (Models) in it, with
   unique names.
2. Every template has a PrimaryPart inside it that is not rotated (the foot).
3. `ScaleMin` / `ScaleMax` are positive, min not above max.
4. Tags sit on the kind of object the world rules ask for, never on a MeshPart. No start tag and
   no zone number in a kit. Attributes from `PositiveAttributes` are positive, and a template
   that carries one is not scalable (the world-builder does not scale attributes).
5. No scripts and no `SpecialMesh` / `BlockMesh`.
6. MeshParts are Anchored with CanCollide, CanQuery and CanTouch off; every other part is
   invisible (Transparency 1) and Anchored.
7. Every MeshId and TextureID is an `rbxassetid://` from the upload list.

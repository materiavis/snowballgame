---
name: Asset task
about: A building kit for the asset-builder agent. Fill every section; the agent stops when something is missing.
labels: ["assets"]
---

## Kit
<!-- Kit name: world/kits/<kit>.rbxmx and tools/kit/<kit>/. -->

## Style reference
<!-- Link (Notion or Materiavis Files). The Look reviewer compares the assets with it (Gate 1). Only the look comes from it; parts, sizes and numbers come from this issue. -->

## Parts
<!-- One block per part. Sizes in studs at scale 1. -->
### <Part>
- Role (prop, obstacle, station shell, ...):
- Tags and on what kind of object (Point, Part or Group; as in WorldRules.TagKinds if listed there), attributes with values:
- Size (width x height x depth):
- Scale range (ScaleMin-ScaleMax, or "none"):
- Variants (how many, what changes between them):
- Triangle budget per mesh:

## Gallery
<!-- Reference sizes to show next to the parts, e.g. a 2 x 5 x 2 character and other objects. -->

## Fix
<!-- What must not change. -->

## Spielraum
<!-- What the agent may decide itself. State explicitly if nothing. -->

## People
<!-- Anyone can take these roles; name them per task. Without them, the gates are Not ready. -->
- Look reviewer (Gate 1):
- Uploader (Gate 2, must be able to upload under the Materiavis group):

## Acceptance criteria
- [ ] Every template is generated from a seed; the generator gives the same files twice
- [ ] Every mesh is within its triangle budget (check.py)
- [ ] `world/kits/<kit>.rbxmx` passes the kit check in `lune run tests`
- [ ] [human] Look review PASS on the PR (Gate 1)
- [ ] [human] Assets uploaded, IDs in `tools/kit/<kit>/upload-list.json`, kit check green (Gate 2)

## Agent
asset-builder

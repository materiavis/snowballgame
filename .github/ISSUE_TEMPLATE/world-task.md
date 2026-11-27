---
name: World task
about: Zones for the world-builder agent. Fill every section; the agent stops when something is missing.
labels: ["world"]
---

## World and zones
<!-- Folder name under world/ and which zones, e.g. world/<world>/, zones 1-5. -->

## Kit
<!-- world/kits/<kit>.rbxmx. It must already be merged to `main`, with every template this task uses. Otherwise the task is Not ready. -->

## Per zone
<!-- One block per zone. Sizes in studs. -->
### Zone NN
- Size (length x width):
- Ground (material, colour, tags):
- Start (where players arrive):
- Objects (template, how many, roughly where):
- Paths (how wide, what must stay free):
- Must be visible from the start:

## Tags the zone check must check
<!-- Optional. Which tag sits on which kind of object: Point (marker or part), Part (one part) or Group (several parts with a main part). Attributes that must be positive. Written into WorldRules (TagKinds, PositiveAttributes). -->

## Limits for the zone check
<!-- Optional. Counts per tag (min/max) and shares (e.g. "40-60 % of <tag> objects carry <attribute>"). Written into WorldRules under Worlds["<world>"]. -->

## Fix
<!-- What must not change. -->

## Spielraum
<!-- What the agent may decide itself. State explicitly if nothing. -->

## Acceptance criteria
- [ ] Every zone is built by `lune run tools/world/build <world>` and passes the zone check
- [ ] 
<!-- [human] criteria need a concrete yes/no question, e.g. "Is every obstacle recognisable from the normal game camera?". Never just "feels good". They go to the END PLAYTEST (Gate 3). -->
- [ ] [human]

## Agent
world-builder

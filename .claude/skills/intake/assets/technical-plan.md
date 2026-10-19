# NNNN — GAME technical intake

**Status:** Proposed
**Plan revision:** 1
**Concept:** NOTION_URL · VERSION · LAST_EDITED
**Concept approval:** Names, date and source evidence
**Repository:** OWNER/REPO · analysis commit SHA
**Intake validation:** Date, checklist evidence and any nonblocking questions

## Context

Technical goals and constraints derived from the approved concept. Link concept
sections rather than copying the entire game design into the repository.

## Decision

### Architecture and responsibilities

Server authority, service/controller responsibilities, startup order, shared
types/configuration, remote contracts and validation. Distinguish existing code
from proposed work. Explain alternatives and tradeoffs where decisions matter.

| Component | Server/client/shared | Responsibility | Dependencies | Concept section |
|---|---|---|---|---|

### Places, Rojo and world assets

| Place | Purpose | Rojo project file | Source paths and Roblox mappings | Teleport boundary |
|---|---|---|---|---|

One project file per Place; identify shared paths used by all relevant Places.
Show the proposed directory tree, per-Place build and serve commands, and how the
current `default.project.json` is retained or migrated in a later issue. Use
placeholders for unknown live IDs, never fabricated IDs.

List `.rbxmx` map areas, their Rojo mapping, one-editor ownership and export/PR
handoff. Explain the proposed terrain solution and any decision still required.

### Data model and failure behaviour

| Data | Type/default | Owning service | Persistence and scope | Concept section |
|---|---|---|---|---|

Address schema version/migration, session locking, autosave, leave/teleport,
load/save failures, concurrency and exactly-once purchase handling where relevant.
If no saved data exists, explain why. Never change a live data format here.

### Milestones (concept 15.1)

| Concept milestone | Required outcome | Actual target date or unset | Existing GitHub milestone |
|---|---|---|---|

### Feature coverage and proposed issues

Use stable keys such as `7.1-ball-growth`, preserving keys on later runs.

| Feature key | Concept section | Launch/later | Milestone | Scope | Dependencies | Existing issue/PR |
|---|---|---|---|---|---|---|

For every row, include a proposed issue body using
`.github/ISSUE_TEMPLATE/dev-task.md`: goal, concept acceptance criteria, technical
checks, Fix, Spielraum, scope and agent. Include requirements outside chapter 7
when they describe additional features. Record optional/excluded items and reasons.

### Verification plan

Automated checks, server/client and save/teleport edge cases, per-Place Rojo
builds, Studio playtests and Jan's mobile check before each release. Separate
future tests from tests actually performed.

## Consequences

Tradeoffs, implementation order, operational limits and migration impact.

## Open questions

| Question | Source | Owner | Blocking? | Default/proposal |
|---|---|---|---|---|

## Manual plan review

Both reviewers must approve the same plan revision before GitHub creation.
Populate evidence only from actual human reviews. Substantive plan or concept
changes require a new revision and renewed approval by both reviewers.

| Reviewer | Approved revision | Review date | Evidence |
|---|---|---|---|
| Miguel | Pending | — | — |
| Yowaldy | Pending | — | — |

## Intake result log

Updated after GitHub operations; this log does not alter the reviewed plan.

| Feature/milestone key | Created/reused/remaining | GitHub URL | Verification or failure |
|---|---|---|---|

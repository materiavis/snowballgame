# Technical documentation

Architecture notes and decisions for snowballgame.
Game design lives in Notion; this folder only explains *how* things are built.

## Architecture decision records (ADRs)

Name files `NNNN-short-title.md`, e.g. `0001-server-authoritative-ball-size.md`:

- **Context:** what problem we had
- **Decision:** what we chose
- **Consequences:** what this makes easier or harder

| # | Decision | Status |
|---|---|---|
| 0001 | [Rojo and Git as source of truth for code](0001-rojo-git-source-of-truth.md) | Accepted |
| 0002 | [Snowball push model, network ownership, collision groups and visual size cap](0002-snowball-push-ownership-size-cap.md) | Proposed |

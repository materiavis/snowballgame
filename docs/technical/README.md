# Technical documentation

Architecture notes and decisions for snowballgame.
Game design lives in Notion; this folder only explains *how* things are built.

## Architecture decision records (ADRs)

Name files `NNNN-short-title.md`, e.g. `0001-server-authoritative-ball-size.md`:

- **Context:** what problem we had
- **Decision:** what we chose
- **Consequences:** what this makes easier or harder

An ADR written in the build loop gets its final status in its own PR: `**Status:** Accepted with merge of PR #NN.` (filled in once the PR exists). The human merge is the acceptance, so nothing changes after the playtests. If the PR closes unmerged, the ADR never reaches `main`.

| # | Decision | Status |
|---|---|---|
| 0001 | [Rojo and Git as source of truth for code](0001-rojo-git-source-of-truth.md) | Accepted |
| 0002 | [Snowball push, network ownership, collision groups and zone optics](0002-snowball-push-ownership-size-cap.md) | Accepted with merge of PR #89 |
| 0003 | [Snow Rush technical intake](0003-snow-rush-intake.md) | Accepted |
| 0004 | [Multi-Place Rojo setup](0004-multi-place-rojo.md) | Accepted (PR #76) |
| 0005 | [Net layer for remotes](0005-net-remotes.md) | Accepted (PR #81) |
| 0006 | [DataService, player data and session locking](0006-player-data.md) | Accepted with merge of PR #84 |
| 0007 | [Economy config, formulas, number format, rarity, RNG and CurrencyService](0007-economy-config.md) | Accepted with merge of PR #87 |
| 0008 | [HUD, window stack and input device tracking](0008-hud-and-windows.md) | Accepted with merge of PR #92 |
| 0009 | [Map contract: tags and attributes for World 1 zones and the Lobby](0009-map-contract.md) | Accepted with merge of PR #106 |
| 0010 | [Upgrades, the UpgradeBuy remote and the upgrade stand](0010-upgrades.md) | Accepted with merge of PR #114 |

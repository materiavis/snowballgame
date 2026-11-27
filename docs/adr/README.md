# Architecture decision records (ADRs)

This folder holds decisions that apply beyond a single task: they affect several agents, systems or games, or are hard to change later.
Decisions that only affect one task or plan go into that plan (e.g. `docs/kits/<kit>-plan.md`).
Architecture notes that are not decisions go into `docs/technical/`.
Game design lives in Notion; this folder only explains *how* things are built.

## Naming

`NNNN-short-title.md`, numbered in order, e.g. `0018-reputation-system.md`.
Take the next free number from the index below.

## Content

Every ADR contains (see `CLAUDE.md`, "What a decision contains"):

- **Status:** Proposed, Accepted or Superseded by ADR NNNN
- **Context:** the question and why it came up, with the source (issue or PR)
- **Decision:** what we chose
- **Reason:** why, in 1–2 sentences
- **Rejected options:** what else was considered and why not
- **Consequences:** what this makes easier or harder

## Status

An ADR written in the build loop gets its final status in its own PR: `**Status:** Accepted with merge of PR #NN.` (filled in once the PR exists). The human merge is the acceptance, so nothing changes after the playtests. If the PR closes unmerged, the ADR never reaches `main`.

An accepted ADR is not rewritten. If a decision changes, write a new ADR and set the old one to `Superseded by ADR NNNN`.

## Index

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
| 0011 | [TravelService, server selection and PresenceStore](0011-travel-service.md) | Accepted with merge of PR #110 |
| 0012 | [Selling at the scale](0012-selling.md) | Accepted with merge of PR #123 |
| 0013 | [Pets and Egg 1 (Vertical Slice slice of 7.9)](0013-pets-egg1.md) | Accepted with merge of PR #125 |
| 0014 | [Zones 1–5, barriers, the zone teleport and the current zone](0014-zones-barriers.md) | Accepted with merge of PR #124 |
| 0015 | [Lobby portals, player counts, first-join arrow, group chest, news board and VIP corner](0015-lobby-portals.md) | Accepted with merge of PR #126 |
| 0016 | [Finds](0016-finds.md) | Accepted with merge of PR #127 |
| 0017 | [Onboarding hints of the first five minutes](0017-onboarding.md) | Accepted with merge of PR #128 |
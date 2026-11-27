# Technical documentation

Architecture notes and decisions for snowballgame.
Game design lives in Notion; this folder only explains *how* things are built.

## Architecture decision records (ADRs)

Name files `NNNN-short-title.md`, e.g. `0001-server-authoritative-ball-size.md`:

- **Context:** what problem we had
- **Decision:** what we chose
- **Consequences:** what this makes easier or harder

An ADR written in the build loop gets its final status in its own PR: `**Status:** Accepted with merge of PR #NN.` (filled in once the PR exists). The human merge is the acceptance, so nothing changes after the playtests. If the PR closes unmerged, the ADR never reaches `main`.
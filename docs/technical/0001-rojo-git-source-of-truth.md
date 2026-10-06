# 0001 — Rojo and Git as source of truth for code

**Status:** Accepted

## Context
Several AI agents and humans work on the same game. Code that only exists inside a Studio place file has no history, no diffs, no review and cannot be edited in parallel worktrees.

## Decision
All scripts live as `.luau` files in this repository and are synced into Studio with Rojo (`default.project.json`). Studio is used for building the world, testing and playtesting, not as the place where code is written.

## Consequences
- Every code change is reviewable and reversible through Git.
- Agents can work in parallel in separate worktrees.
- World geometry and assets built in Studio are not yet versioned. How we store them (place file in Git LFS, `.rbxm` models in the repo, or Studio only) is an open decision.

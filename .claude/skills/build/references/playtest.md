# Local playtester handoff

The authoritative agent is [playtester.md](../../../agents/playtester.md).
Preserve its MCP allowlist, restrictions and `guard-studio-luau.sh` hook. Read its
current definition before each handoff. Studio is shared: schedule one test at a
time, with a single DM coordinating checkout changes. An active playtest blocks
another issue's Studio handoff, not file work in isolated worktrees.

## Host and checkout preparation

The configured Studio MCP runs on the local Windows host via `cmd.exe` and
`%LOCALAPPDATA%\Roblox\mcp.bat`. The documented working launch is a terminal in
the repo, not the VS Code extension:

```bash
claude --agent playtester
```

Supply that session with the issue/PR, branch, expected **full head SHA**, exact
ACs and relevant technical/review evidence. If the DM cannot launch or reach the
local session, return this handoff and WAITING_FOR_PLAYTEST; do not improvise
Studio access in the main session or another agent.

Before testing:

1. Identify the designated main checkout using `git worktree list`; it is not
   the implementation agent's worktree. Its working tree, including untracked
   files, must be clean. Do not stash, delete, reset or overwrite someone else's
   work to make it clean. Ensure no other session needs that checkout right now.
2. Fetch the pushed PR branch and confirm its commit equals the expected full
   SHA. The playtester uses `git checkout --detach origin/<branch>` in this
   checkout because that branch is already checked out in the agent's worktree.
   Confirm `git rev-parse HEAD` after the switch; a branch name alone is not proof.
3. Build `build/test.rbxl` from that revision and the applicable Rojo project
   (pass its project file explicitly when it is not the default).
   Open this local test Place, with `rojo serve` for that same project running
   in the designated checkout and Studio's Rojo plugin connected. If setup is
   unavailable, request the local preparation and leave the test pending.
4. The playtester verifies `game.PlaceId == 0` and the expected scripts have
   synced before Play. No test in a published Place. Map/project changes that
   require rebuilding/reopening the Place must be included, not assumed synced.

The existing agent also fetches and checks out the branch. It must verify that
this still resolves to the supplied SHA and abort on a mismatch; the DM checks
the SHA again when accepting the report. The current playtester accepts only
`build/test.rbxl`. For multiple affected Places, test serially: build each
approved project into that fixed path, reopen it and reconnect the matching Rojo
project before its test. Retain project-specific evidence for each; the distinct
technical build outputs alone do not prove that Place was played.

## Evidence and cleanup

Require a PR comment with the agent's AC-by-AC table, observation/screenshot
description, Console errors/warnings, overall PASS/FAIL and reproduction hints
for failures. Put the **full tested SHA** in the report (in addition to the
agent's short SHA heading). Supply command/DM review evidence for non-runtime
criteria so the table covers the entire issue without asking the playtester to
claim an unseen check passed.

Use the agent's console fallback through `LogService:GetLogHistory()` if
`console_output` is unavailable. Its `execute_luau` remains read-only and guarded.
Missing input capability, partial coverage or missing Console evidence stays
pending. Screenshot descriptions are valid where `gh` cannot attach the image;
do not invent attachment URLs or observations.

Always ask the playtester to stop Play and return the designated checkout to
`main` as its existing cleanup requires, including after an interrupted test
where cleanup is possible. Verify that cleanup happened before releasing the
shared Studio slot; if it failed, report it and block other Studio tests until
resolved. Never use a destructive reset to clean up. A cleanup checkout is not
permission to commit, push or merge into `main`.

On FAIL, the DM batches these findings with any other failures and dispatches
the next correction in the same implementation worktree. On PASS, compare the
tested SHA with the PR's live head; later commits need new checks and playtest.

# CLAUDE.md — snowballgame

Rules for Claude Code and every subagent working in this repository.
Read this file fully before starting any task.

## 1. What this repo is

The Roblox game "Snowball Game" (working title) by Materiavis.
Players roll a growing snowball, collect finds, sell the ball for coins and buy upgrades.

This repo holds the code and technical docs only. It is **not** the place for game design.

## 2. Sources of truth

| What | Where |
|---|---|
| Game design, features, story, priorities, decisions | Notion (owned by the Creative/Product side) |
| Game concept page | Notion → Wissen & Dokumente → Roblox Games Knowledgebase → "SCHNEEBALL GAME" |
| Development tasks | GitHub Issues in `materiavis/snowballgame` |
| Code and technical documentation | This repository |
| Development reports | Notion |

- If a requirement is unclear or missing, do **not** invent game design. Ask, or note the open question in the issue.
- Your own memory or chat history is never a source of truth. If it matters, it belongs in Notion, an issue or `docs/technical/`.

## 3. Roles

- **Project Owner (humans):** final say on game direction, big gameplay changes, releases, milestones, conflicts.
- **ChatGPT, Creative/Product Manager:** decides *what* gets built and *why*. Writes feature specs in Notion.
- **Claude Code main session, Development Manager:** decides *how*. Turns specs into issues, delegates to subagents, reviews PRs, integrates, writes reports.
- **Subagents** (`.claude/agents/`): do one clearly scoped task each.

## 4. Repository layout

```
src/
  server/          -> ServerScriptService.Server   (init.server.luau starts Services/*)
    Services/      -> one ModuleScript per server system, exposes Start()
  client/          -> StarterPlayerScripts.Client  (init.client.luau starts Controllers/*)
    Controllers/   -> one ModuleScript per client system, exposes Start()
  shared/          -> ReplicatedStorage.Shared     (config, types, pure helpers)
docs/technical/    -> architecture notes and decisions (ADRs)
default.project.json -> Rojo mapping. Change only when adding a new top-level location.
```

Code lives as files in Git and is synced into Studio with Rojo.
Never write scripts only inside Studio: anything not in Git does not exist.

## 5. Coding standards

- Language: Luau, `--!strict` at the top of every file.
- File extension `.luau`. Format with StyLua, lint with Selene (`std = "roblox"`). Both must pass before a PR.
- Naming: `PascalCase` for modules, services, controllers, types and Instances; `camelCase` for locals and functions; `UPPER_SNAKE_CASE` for true constants.
- Services end in `Service` (`BallService`), controllers end in `Controller` (`BallController`).
- One module = one responsibility. No file over ~400 lines without a reason in the PR.
- Gameplay numbers (growth rate, prices, limits) go in `src/shared/Config.luau` or a dedicated config module, never hard-coded in logic.
- Comments explain *why*, not *what*.

## 6. Roblox architecture rules

- **The server is authoritative.** Coins, ball size, inventory, pets and unlocks are decided on the server. The client only requests and displays.
- Every RemoteEvent / RemoteFunction handler on the server validates type, range and rate of its arguments.
- Never trust values sent by the client (e.g. "my ball is size 500").
- DataStore access goes through one data service only, with retries and session locking. No other module calls DataStoreService directly.
- No `HttpService` calls, no `loadstring`, no `require(<assetId>)`.
- Large growing physics objects are a known risk (jitter, falling through terrain, mobile performance). Test performance on mobile settings early.

## 7. Git workflow

- **Never commit or push to `main`.** Every change goes through a branch and a pull request.
- One issue → one branch → one PR. Branch names: `feat/<issue>-<slug>`, `fix/<issue>-<slug>`, `chore/<issue>-<slug>`, `docs/<issue>-<slug>`.
  Example: `feat/12-ball-growth`.
- Commits: short imperative subject, reference the issue: `Add ball growth on snow contact (#12)`.
- PR description uses the template and links the issue with `Closes #<n>`.
- The Development Manager may merge PRs into branches other than `main` only after technical checks, acceptance review and applicable playtests pass for the current PR head. Recheck the live base and head before merging; bind the merge to the verified head SHA.
- **Only humans merge PRs into `main`.** The Development Manager must hand off a ready PR and never merge it, enable auto-merge into `main`, or retarget it to bypass this rule. Subagents never merge any PR.
- No force pushes, no history rewrites on shared branches.

## 8. Worktrees and parallel work

- Subagents that write code run with `isolation: worktree`: each gets its own temporary copy of the repo on its own branch.
- Code work may run in parallel. **Roblox Studio is shared and is used by one agent at a time** (the playtester).
- A subagent only touches files inside the scope of its issue. If it needs to change something outside that scope, it stops and reports back.

## 9. Roblox Studio and MCP

- Only the `playtester` agent uses the Studio MCP. Code-writing agents work on files only.
- Treat Luau execution in Studio as privileged: it can write DataStores, publish places and make HTTP requests.
- Never publish a place, never write to production DataStores, never change game settings from an agent.
- Test only in the local, repo-built test Place `build/test.rbxl`, with `game.PlaceId == 0`. For multiple Places, build and open each approved project at that path separately. Only the playtester uses Studio MCP, with its existing read-only hook and tool restrictions.

## 10. Third-party assets

- Nothing from the Creator Store goes into the game without a `model-auditor` report.
- Assets with scripts are rejected by default unless the scripts are understood and needed.

## 11. Definition of Done

A task is done when:
1. The code does what the issue asks, nothing more.
2. `stylua --check src` and `selene src` pass.
3. `rojo build -o build/test.rbxl` succeeds.
4. Every acceptance criterion has review/check evidence; relevant runtime behaviour has a Playtester PASS for the current PR head, with per-criterion evidence and no errors from game scripts. A tooling/docs-only change may explain why Studio is inapplicable. Unavailable Studio access leaves a feature pending, not passed.
5. The PR is open, uses the template, links the issue and lists open questions.
6. Technical docs in `docs/technical/` are updated if architecture changed.

For tooling/docs-only changes, an inapplicable formatting, lint, build or Studio check may be recorded as not applicable with a concrete reason. Feature work requires every applicable check; unavailable tooling is blocked, never a pass or an applicability exception.

## 12. Reports

After a feature is merged, the Development Manager writes a short report to Notion:
what was built, linked PRs, what was tested, open points, next steps. German is fine.

## 13. Escalate to the humans when

- a spec in Notion contradicts itself or the code,
- a change would alter core gameplay, monetisation or the save-data format,
- something requires publishing, spending Robux or touching live data,
- an agent is unsure whether something is allowed.
- the `/build` loop still fails after **three correction rounds** following the initial implementation. Technical, review and playtest failures share this budget. Preserve the count on the issue across restarts; stop further fixes and merging until an owner resolves the blocker or explicitly authorizes a new budget.

## 14. Releases

- Before any release, a mobile check issue assigned to Jan (label `mobile`) must exist for that release and be **closed**. Without it, the release is blocked.

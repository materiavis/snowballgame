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
- **Owners on GitHub:** `mcmateriavis` (Miguel), `janmateriavis` (Jan), `marcolecluse` (Marco), `YKITler` (Yowaldy). END PLAYTEST requests mention them.

## 4. Repository layout

```
src/
  server/          -> ServerScriptService.Server   (init.server.luau starts Services/*)
    Services/      -> one ModuleScript per server system, exposes Start()
  client/          -> StarterPlayerScripts.Client  (init.client.luau starts Controllers/*)
    Controllers/   -> one ModuleScript per client system, exposes Start()
  shared/          -> ReplicatedStorage.Shared     (config, types, pure helpers)
  places/          -> social, lobby, simulator, arena; each with server/ and client/, mounted per Place
places/            -> one Rojo project per Place (<place>.project.json). Change when adding a Place or top-level location.
world/             -> map areas as .rbxmx, mapped per Place
docs/technical/    -> architecture notes and decisions (ADRs)
default.project.json -> alias of places/world1.project.json. Holds no mapping of its own.
```

Code lives as files in Git and is synced into Studio with Rojo.
Never write scripts only inside Studio: anything not in Git does not exist.

## 5. Coding standards

- Language: Luau, `--!strict` at the top of every file.
- File extension `.luau`. Format with StyLua, lint with Selene (`std = "roblox"`). Both must pass before a PR.
- Naming: `PascalCase` for modules, services, controllers, types and Instances; `camelCase` for locals and functions; `UPPER_SNAKE_CASE` for true constants.
- Services end in `Service` (`BallService`), controllers end in `Controller` (`BallController`).
- One module = one responsibility. No file over ~400 lines without a reason in the PR.
- Gameplay numbers (growth rate, prices, limits) go in `src/shared/Config/` or a dedicated config module, never hard-coded in logic.
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
- **Branch cleanup is the Development Manager's job** (`/cleanup`), not a GitHub setting. It deletes its merged issue branches locally and on GitHub:
  - directly after the merge, when no acceptance criterion of the PR waits for the END PLAYTEST;
  - otherwise only after the milestone's END PLAYTEST issue is closed with every item PASS.

  The agent worktree is removed directly after the merge in both cases. Every deletion and every kept branch is recorded on the Pull Request with reason and SHA, so owners can review the timing and restore a branch.
- Deleting is only allowed with `git worktree remove` (never `--force`), `git branch -d` (never `-D`) and `git push origin --delete <branch>` for one issue branch per command. `.claude/hooks/guard-git-cleanup.sh` blocks every other deletion and every force push.
- **Never deleted by the DM:** `main`, branches of open PRs, unmerged commits, branches of PRs closed without merge (unless an owner wrote `Owner decision: delete branch` on the PR), branches the DM did not create (e.g. `test/…`, integration branches) and the playtest worktree. Humans delete those themselves.

## 8. Worktrees and parallel work

- Subagents that write code run with `isolation: worktree`: each gets its own temporary copy of the repo on its own branch.
- Code work may run in parallel. **Roblox Studio is shared and is used by one agent at a time** (the playtester).
- A subagent only touches files inside the scope of its issue. If it needs to change something outside that scope, it stops and reports back.

## 9. Roblox Studio and MCP

- Only the `playtester` agent uses the Studio MCP. Code-writing agents work on files only.
- Treat Luau execution in Studio as privileged: it can write DataStores, publish places and make HTTP requests.
- Never publish a place, never write to production DataStores, never change game settings from an agent.
- Test only in the local test Place `build/test.rbxl` of the playtest worktree, built with `rojo build` at the tested SHA, with `game.PlaceId == 0`. For multiple Places, build and open each Place separately. No `rojo serve` during a playtest.
- The playtester is started from the main checkout on `main`, so its definition and hook always come from `main`, never from a Pull Request state. During Play it may set the Studio switches documented in an ADR (`game.ServerScriptService:SetAttribute`) and nothing else; its hook blocks every other change.
- If the playtester cannot reach a state an acceptance criterion needs through input, the implementation adds a documented Studio switch for it, so the criterion can be tested without a person.

## 10. Third-party assets

- Nothing from the Creator Store goes into the game without a `model-auditor` report.
- Assets with scripts are rejected by default unless the scripts are understood and needed.

## 11. Definition of Done

A task is done when:
1. The code does what the issue asks, nothing more.
2. `stylua --check src` and `selene src` pass.
3. `rojo build places/<place>.project.json -o build/test.rbxl` succeeds for every affected Place (`lobby`, `world1`, `arena`).
4. Every acceptance criterion has review/check evidence; relevant runtime behaviour has a Playtester PASS for the current PR head, with per-criterion evidence and no errors from game scripts. Criteria the playtester leaves as NEEDS HUMAN REVIEW are on the milestone's END PLAYTEST list instead; ERROR is never a pass. A tooling/docs-only change may explain why Studio is inapplicable. Unavailable Studio access leaves a feature pending, not passed.
5. The PR is open, uses the template, links the issue and lists open questions.
6. Technical docs in `docs/technical/` are updated if architecture changed.

For tooling/docs-only changes, an inapplicable formatting, lint, build or Studio check may be recorded as not applicable with a concrete reason. Feature work requires every applicable check; unavailable tooling is blocked, never a pass or an applicability exception.

## 12. Reports

After a feature is merged, the Development Manager writes a short report to Notion:
what was built, linked PRs, what was tested, open points, next steps. German is fine.

Use `/report <PR-number-or-URL>` via [.claude/skills/report/SKILL.md](.claude/skills/report/SKILL.md), after verifying the actual merge. It also runs the END PLAYTEST milestone check and the cleanup from section 7. Repeated runs update the same report by repository/PR identity. Report missing or stale test evidence honestly; an integration-branch merge is not a release.

Reports belong in notion under this link: https://app.notion.com/p/40cc1165e2b980748f41ce514835693e, discover and verify the actual container before writing. If missing or inaccessible, return a copy-ready report and the blocker instead of saving to a fallback destination.

## 13. Escalate to the humans when

- a spec in Notion contradicts itself or the code,
- a change would alter core gameplay, monetisation or the save-data format,
- something requires publishing, spending Robux or touching live data,
- an agent is unsure whether something is allowed.
- an acceptance criterion stays ERROR because it cannot be made testable for the playtester. Only an owner may move it to the END PLAYTEST list, recorded on the issue.
- the `/build` loop still fails after **three correction rounds** following the initial implementation. Technical, review and playtest failures share this budget. Preserve the count on the issue across restarts; stop further fixes and merging until an owner resolves the blocker or explicitly authorizes a new budget.

## 14. Milestones and releases

- Every milestone ends with an END PLAYTEST by a human: one issue `END PLAYTEST – <milestone>` (label `end-playtest`) that the Development Manager keeps with `/end-playtest`. It lists the milestone goals and every acceptance criterion left as NEEDS HUMAN REVIEW. A milestone is closed only after that issue is closed with every item PASS. Humans close the END PLAYTEST issue and the milestone; the DM never does.
- Before any release, a mobile check issue assigned to Jan (label `mobile`) must exist for that release and be **closed**. Without it, the release is blocked.

## 15. Files (Materiavis Files, Nextcloud)

Binary and source files live in **Materiavis Files** (https://files.materiavis.ch), not in this repo and not in Notion.
Sources of truth stay as above: **Notion = what/why, GitHub = code + technical docs, Files = binary/source files.**

- **Files is for:** concept art, moodboards, references, source assets (`.blend`, `.fbx`, `.psd`, `.wav`), marketing material, playtest recordings, exports.
- **Never in Files:** game code, Luau scripts, Rojo model files (→ this repo), decisions/specs (→ Notion), passwords/keys (→ Vaultwarden).
- **Link, don't copy:** issues and Notion pages reference files by link. Don't re-upload a file into Notion or the repo.
- **AIs write only to the team folder `AI-Output`** (generated docs, image prompts, reports). Moving a file into `Materiavis/...` is a human decision.
- **AIs never delete or move** files outside `AI-Output` unless a person explicitly asks for that specific file.
- **Paths:** `Materiavis/02_Games/<Game>/<Area>/<yyyy-mm-dd>_<short-name>_v<n>.<ext>`, e.g. `Materiavis/02_Games/SnowRush/Concept/2026-11-12_snowball-skins_v2.png`.
- **New files without a clear home** go to `Materiavis/00_Inbox` (and a ping in Discord `#dev-updates`).
- **Creator Store / third-party models** are never stored there as "approved"; they go through the Model Auditor agent first (section 10).
- **Files tagged `ai-hidden`** are off-limits for AIs (the MCP server hides them).

MCP servers in `.mcp.json`:

| Server | Account | Who uses it |
|---|---|---|
| `materiavis-files` | the person who logs in (OAuth) | the Claude Code main session |
| `materiavis-files-agent` | `agent`: reads everything, writes only `AI-Output`, cannot share | subagents. Give them only `mcp__materiavis-files-agent__*` in `tools:`, never `materiavis-files` |

The agent's app password comes from the environment variable `NC_AGENT_APP_PASSWORD` on your machine. It is **never** written into this repo (it is public), a prompt, an issue or a log.

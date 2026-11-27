# CLAUDE.md — snowballgame

Rules for Claude Code and every subagent working in this repository.
Read this file fully before starting any task.
As Development Manager, you make technical decisions yourself. You don't
ask an owner. You record the decision in writing.


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
- Your own memory or chat history is never a source of truth. If it matters, it belongs in Notion, an issue, "docs/adr/" or "docs/technical/".

### What you decide yourself
Anything about *how*, for example:
- architecture, data models, module and file structure
- budgets and limits (triangles, parts, decoration count per zone)
- number of seeds and variants, tags and attributes
- order of batches and tasks, splitting work into issues
- starting values for anything that gets tuned during playtesting

### What you don't decide yourself

- style, look, story and game feel: send these to Marco or ChatGPT, in
  plain language, with one suggestion per question
- earlier decisions by an owner: never override them silently. If a technical
  reason speaks against one (e.g. an owner left a config value empty on
  purpose, and your task would need it filled), explain the reason and ask
  before you change it.
- anything that costs money, changes permissions or security, or cannot
  be undone (upload, publish, DataStore, API keys): an owner decides

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
docs/technical/ -> architecture notes (no decisions)
docs/kits/<kit>-plan.md    -> for
  decisions that only affect a task or a plan
docs/adr/NNNN-<title>.md   -> for
  decisions that apply beyond a task, meaning they affect several
  agents, systems or games, or are hard to change later
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
- **Fetch before every push.** Run `git fetch origin <branch>` and check `git log HEAD..origin/<branch>`. If the remote has a commit you did not make (e.g. an owner fixed something directly on an agent branch), do not overwrite it and do not rebase. Stop and report the commit SHA and author on the PR.
- **Branch cleanup is the Development Manager's job** (`/cleanup`), not a GitHub setting. It deletes its merged issue branches locally and on GitHub:
  - directly after the merge, when no acceptance criterion of the PR waits for the END PLAYTEST;
  - otherwise only after the milestone's END PLAYTEST issue is closed with every item PASS.

  The agent worktree is removed directly after the merge in both cases. Every deletion and every kept branch is recorded on the Pull Request with reason and SHA, so owners can review the timing and restore a branch.

- If a step is blocked and needs an answer from the owners, stop only that step: mark it `Not ready` in its issue, name what is missing, and keep working on everything that does not depend on it.

- Deleting is only allowed with `git worktree remove` (never `--force`), `git branch -d` (never `-D`) and `git push origin --delete <branch>` for one issue branch per command. `.claude/hooks/guard-git-cleanup.sh` blocks every other deletion and every force push.
- **Never deleted by the DM:** `main`, branches of open PRs, unmerged commits, branches of PRs closed without merge (unless an owner wrote `Owner decision: delete branch` on the PR), branches the DM did not create (e.g. `test/…`, integration branches) and the playtest worktree. Humans delete those themselves.

## 8. Worktrees and parallel work

- Subagents that write code run with `isolation: worktree`: each gets its own temporary copy of the repo on its own branch.
- Code work may run in parallel. **Roblox Studio is shared and is used by one agent at a time** (the playtester).
- A subagent only touches files inside the scope of its issue. If it needs to change something outside that scope, it stops and reports back.
- **Check preconditions before you start.** At the start of every task, check what it needs: the MCP servers it uses are connected, the PRs or kits it builds on are merged to `main`, the required environment variables are set. Record each result (PASS/FAIL) in the issue or plan. If one fails, stop the steps that depend on it and report it. Never work around it: no copies from unmerged branches, no substitute tools, no guessed values.
  - The world-builder never starts a world task while the kit it needs is not merged to `main`.

## 9. Roblox Studio and MCP

- Only the `playtester` agent uses the Studio MCP. Code-writing agents work on files only.
- Treat Luau execution in Studio as privileged: it can write DataStores, publish places and make HTTP requests.
- Never publish a place, never write to production DataStores, never change game settings from an agent.
- Test only in the local test Place `build/test.rbxl` of the playtest worktree, built with `rojo build` at the tested SHA, with `game.PlaceId == 0`. For multiple Places, build and open each Place separately. No `rojo serve` during a playtest.
- The playtester is started from the main checkout on `main`, so its definition and hook always come from `main`, never from a Pull Request state. During Play it may set the Studio switches documented in an ADR (`game.ServerScriptService:SetAttribute`) and nothing else; its hook blocks every other change.
- Never `require` a module from `execute_luau`: it starts a second instance of that module (e.g. a second DataService that loads a profile). Read state through the attributes documented in an ADR. The hook blocks every `require`, `getfenv` and `setfenv`; `.claude/hooks/test-guard-studio-luau.sh` is its regression test.
- If the playtester cannot reach a state an acceptance criterion needs through input, the implementation adds a documented Studio switch for it, so the criterion can be tested without a person.
- Attention! **MCP servers connect only when the session starts.** If a server is missing because a command is not in `PATH` or an environment variable is not set, ask for a full restart of VS Code after the fix. An `export` in the terminal does not reach a session that is already running.

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

### What a decision contains

Every decision includes:
- the question
- the decision
- the reason, in 1–2 sentences
- the rejected options
- the source (issue or PR)

## 12. Reports

After a feature is merged, the Development Manager writes a short report to Notion:
what was built, linked PRs, what was tested, open points, next steps. German is fine.

Use `/report <PR-number-or-URL>` via [.claude/skills/report/SKILL.md](.claude/skills/report/SKILL.md), after verifying the actual merge. It also runs the END PLAYTEST milestone check and the cleanup from section 7. Repeated runs update the same report by repository/PR identity. Report missing or stale test evidence honestly; an integration-branch merge is not a release.

Reports belong in notion under this link: https://app.notion.com/p/40cc1165e2b980748f41ce514835693e, discover and verify the actual container before writing. If missing or inaccessible, return a copy-ready report and the blocker instead of saving to a fallback destination.

Record the decision in the same pull request as the implementation. In
your report, mention it briefly with a link, so owners see it during
review and can object.

- Every human intervention in a log gets one of three types:
  - **Planned gate:** a step where this file says a human acts (section 16).
  - **One-time setup:** something set up once that stays (installing a tool, setting a password, creating a label).
  - **Unplanned intervention:** anything else a human had to do to keep the work going.
  Only unplanned interventions count as candidates for automation.


**Plans and logs: full text in the repo, summary in Notion**

- The full plan or log is a file in the repo (e.g. `docs/kits/<kit>-plan.md`). Edit it only there.
- Notion gets a summary of at most 5 lines: goal, current status, open questions for the owners, link to the file on GitHub.
- Write the summary as one sub-page per plan under Reports: https://app.notion.com/p/425c1165e2b980d9a02ce51ca81bcb93. When the status or the open questions change, update that sub-page instead of creating a new one.
- Never copy tables, decisions or log entries into Notion. Link to them.

## 13. Escalate to the humans when

- a spec in Notion contradicts itself or the code,
- a change would alter core gameplay, monetisation or the save-data format,
- something requires publishing, spending Robux or touching live data,
- an agent is unsure whether something is allowed.
- an acceptance criterion stays ERROR because it cannot be made testable for the playtester. Only an owner may move it to the END PLAYTEST list, recorded on the issue.
- the `/build` loop still fails after **three correction rounds** following the initial implementation. Technical, review and playtest failures share this budget. Preserve the count on the issue across restarts; stop further fixes and merging until an owner resolves the blocker or explicitly authorizes a new budget.
- an asset kit gets its third Look review FAIL (section 16, Gate 1).

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

## 16. Human gates

Three steps in the workflow wait for a human. A gate blocks only the work that depends on it; independent work keeps running. Mark every dependent step `Not ready` in its issue and name the gate it waits for.

| Gate | Question | Blocks | Does not block |
|---|---|---|---|
| 1. Look Review | Does the asset look good enough to upload? | the upload and the next asset round | other tasks |
| 2. Upload | Are the assets uploaded under the Materiavis group and recorded in the upload list? | the kit file step and all work that needs this kit | independent tasks in the same batch |
| 3. END PLAYTEST | Does the integrated result work and feel right for people? | closing the milestone | merging the PR |

If an asset task names no reviewer, uploader or style reference, mark the dependent step `Not ready` and ask the owners on the issue.

### Gate 1: Look Review

- **When:** the asset agent has built the first meshes and opened a PR.
- The agent puts a gallery of all parts, shown next to each other for size comparison, into Materiavis Files under `AI-Output/` (section 15). The PR links that folder; reviewers must be able to open it without asking.
- The reviewer named in the asset task compares the assets with the style reference of that task and writes the result as a PR comment.
- Comment format: `Look review: PASS` or `Look review: FAIL`, followed by the feedback.
- Only a PASS written after the latest commit on the PR counts. No upload starts before that.
- On FAIL, the agent starts a new round with that feedback.
- After **three Look review FAILs** on the same kit, stop and escalate to the owners (section 13). They decide whether to start again with a fresh agent session or to improve the asset agent first. Do not start a fourth round on your own.
- Gate 1 judges the asset on its own. It does not replace the playtest.

### Gate 2: Upload

- After a Look Review PASS, the Development Manager opens one issue `Upload <kit>` with the label `needs-upload` and assigns it to the uploader named in the asset task. The issue lists the PR link, the assets to upload and the expected entries of `tools/kit/<kit>/upload-list.json`.
- The uploader uploads the assets in Studio, checks import and scale there, and enters the asset IDs in the upload list.
- The gate passes only when the upload list in the repo is filled, its entries match the uploaded assets and the kit checks pass. A message like "uploaded", or removing the label, is not enough.
- If the uploader commits to the PR branch, the fetch-before-push rule in section 7 applies.

### Gate 3: END PLAYTEST

- Applies to acceptance criteria that need human judgement: look, feel, device or multiplayer checks. Mark them in the issue with `[human]` and a concrete yes/no question, e.g. "Is the obstacle recognisable at once from the normal game camera?", never just "feels good".
- The playtester reports these criteria as NEEDS HUMAN REVIEW. The Development Manager puts them on the milestone's END PLAYTEST issue (section 14). They block the milestone, not the PR.
- A human checks the result and writes PASS or FAIL per criterion on the END PLAYTEST issue, as described in `/end-playtest`. On FAIL, the Development Manager opens a bug issue in the same milestone. Humans close the END PLAYTEST issue and the milestone.
- A technical failure of the playtester is ERROR, never NEEDS HUMAN REVIEW.
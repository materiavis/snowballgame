# snowballgame

Roblox game by Materiavis. Roll a snowball, make it huge, sell it, upgrade, repeat.

- **Game design & decisions:** Notion → Roblox Games Knowledgebase → "SCHNEEBALL GAME"
- **Dev tasks:** GitHub Issues
- **Rules for humans and AI agents:** [`CLAUDE.md`](CLAUDE.md)

## Setup (once per machine)

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then in this folder run:
   ```sh
   rokit install
   ```
   This installs the pinned versions of Rojo, Selene and StyLua from `rokit.toml`.
2. Install the Rojo plugin in Roblox Studio:
   ```sh
   rojo plugin install
   ```
3. Install the GitHub CLI and log in: `gh auth login`
4. Install Claude Code.

## Daily workflow

```sh
rojo serve              # then click "Connect" in the Rojo plugin in Studio
claude                  # start the Development Manager session in this folder
```

Build a place file without Studio:
```sh
rojo build -o build/test.rbxl
```

Lint and format:
```sh
stylua src
selene src
```

## Issue build-loop

In the Claude Code Development Manager session, run `/build <issue-number-or-URL>`.
The [build skill](.claude/skills/build/SKILL.md) takes one prepared GitHub issue
from intake, delegates implementation in an isolated worktree, checks formatting,
Selene and Rojo, reviews acceptance criteria and coordinates a Studio playtest.
Repository tooling issues can also use the loop without a game concept.

FAIL findings return to the same implementation agent. The initial attempt is
followed by at most three correction rounds, tracked on the issue even across
restarts; unresolved failures then need owner intervention. Repeat the same
`/build <issue>` to resume existing work rather than create another branch/PR.

Playtests run one at a time on the local Studio host. Start the configured
playtester in a separate terminal with `claude --agent playtester`, using the
DM's PR/branch/SHA and acceptance-criteria handoff. The designated main checkout
must be clean, with the repo-built test Place open and Rojo connected. A missing
Studio connection leaves testing pending. See the
[playtester handoff](.claude/skills/build/references/playtest.md).

The DM may merge a passing PR into an approved branch other than `main`.
**Merges into `main` remain human-only.** Existing tool permission prompts still
apply. After an actual merge, the evidence is handed off for a Development Report;
the separate `/report` skill is not included here. This command does not release
the game or replace Jan's mobile release check.

## Agents

Defined in `.claude/agents/`:

| Agent | Does | Studio access | Worktree |
|---|---|---|---|
| gameplay-engineer | gameplay features | no | yes |
| systems-engineer | data, networking, core systems | no | yes |
| playtester | syncs a branch, playtests, reports | yes (only one) | no |
| model-auditor | security review of third-party assets | no | no |

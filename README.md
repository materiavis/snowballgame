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

## Concept intake

In Claude Code, run `/intake <Notion concept URL>`. The
[intake skill](.claude/skills/intake/SKILL.md) checks that the concept is
**Freigegeben für Development** and its release checklist is complete, then
drafts a technical ADR in `docs/technical/`.

The command stops for **Miguel and Yowaldy** to review the plan. Resume with
`/intake <Notion concept URL> <ADR path>` after both approvals are recorded for
that revision. Only then does it create/reuse GitHub milestones and one issue
per feature. Concept or substantive plan changes require renewed review.

The session needs a Notion connection and GitHub access (connected tools or an
authenticated `gh` CLI with milestone and issue permissions). Existing tool
permission prompts still apply. This is a Claude Code skill; it is not a shell
command. It prepares work for the separate build-loop.

## Agents

Defined in `.claude/agents/`:

| Agent | Does | Studio access | Worktree |
|---|---|---|---|
| gameplay-engineer | gameplay features | no | yes |
| systems-engineer | data, networking, core systems | no | yes |
| playtester | syncs a branch, playtests, reports | yes (only one) | no |
| model-auditor | security review of third-party assets | no | no |

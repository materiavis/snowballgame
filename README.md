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

## Agents

Defined in `.claude/agents/`:

| Agent | Does | Studio access | Worktree |
|---|---|---|---|
| gameplay-engineer | gameplay features | no | yes |
| systems-engineer | data, networking, core systems | no | yes |
| playtester | syncs a branch, playtests, reports | yes (only one) | no |
| model-auditor | security review of third-party assets | no | no |

# Playtester handoff

The authoritative agent is [playtester.md](../../../agents/playtester.md).
Preserve its MCP allowlist, restrictions and `guard-studio-luau.sh` hook. Read its
current definition before each handoff. Studio is shared: schedule one test at a
time, with a single DM coordinating the playtest worktree. An active playtest
blocks another issue's Studio handoff, not file work in isolated worktrees.

## Two checkouts

- **Control checkout:** the main checkout of the repository, on `main`. The
  playtester is started here, so its definition and hook always come from
  `main`. Never check out a Pull Request state in it for a playtest.
- **Playtest worktree:** a dedicated, detached worktree next to it, e.g.
  `../snowballgame-playtest`, set to the tested SHA. Studio opens the Place built
  there. It holds no work of its own; only the ignored `build/` may differ.

The playtester never checks out, builds or serves anything. It reads files of the
tested state with `git show <SHA>:<path>` and verifies that Studio shows that SHA.

## Setup per Place (a human until Phase 2, then the DM)

1. Close Studio **completely**, before every run including the first. Reloading
   the file or reconnecting is not enough.
2. `git fetch origin` in the control checkout.
3. Set the playtest worktree to the full SHA:
   - first time: `git worktree add --detach ../snowballgame-playtest <SHA>`
   - afterwards: `git -C ../snowballgame-playtest checkout --detach <SHA>`
   - confirm `git -C ../snowballgame-playtest rev-parse HEAD` equals the SHA and
     `git -C ../snowballgame-playtest status --porcelain` is empty. Do not stash,
     reset or delete anything to make it clean; report it instead.
4. In the playtest worktree: `rojo build places/<place>.project.json -o build/test.rbxl`.
5. Confirm `build/test.rbxl.lock` is gone, then open
   `../snowballgame-playtest/build/test.rbxl` in Studio with the Studio MCP enabled.
6. **No `rojo serve` and no Rojo plugin connection during a playtest.** The built
   file is the tested state; a live sync would overwrite it from another checkout.
7. Start the playtester in its own session from the control checkout
   (`claude --agent playtester`) and give it the handoff prompt. Not the VS Code
   extension and not a nested subagent: its MCP server only loads in its own
   session. Never improvise Studio access in the main session or another agent.

For several affected Places (`lobby`, `world1`, `arena`), repeat setup and
playtest per Place, serially, each starting with step 1, so no run happens in a
previous Place's build. CI's separate build outputs do not prove a Place was played.

## Handoff prompt

One self-contained prompt. Until Phase 2 a human pastes it; afterwards the DM
passes the same text to the playtester session. Use actual values:

```
Playtest
Repo: <owner/name>
Pull Request: #<pr> · Issue: #<issue> · Branch: <branch> · Base: <base>
SHA: <full head SHA>
Place: <place> · Studio file: ../snowballgame-playtest/build/test.rbxl
Acceptance Criteria:
AC1 <criterion>
AC2 [human] <criterion>
DM CHECK: AC<n> (<command or review evidence>), …
Hints: <ADR sections, Studio switches, fixtures; read with git show <SHA>:<path>>
```

Number the ACs as in the issue and keep their `[human]` markers. Supply DM CHECK
evidence for technical and documentation ACs so the playtester never has to
claim an unseen check. Only for a trial of a changed playtester, add
`Playtester branch (trial): <branch>` and keep the control checkout on that
branch during the run.

Record the setup commands and the prompt on the issue as WAITING_FOR_PLAYTEST,
then stop. Resume with the same `/build <issue>` once the report is posted.

## Results and categories

Per AC the playtester reports PASS, FAIL, ERROR, NEEDS HUMAN REVIEW or DM CHECK,
and an Overall of PASS, FAIL or ERROR.

NEEDS HUMAN REVIEW is limited to five categories:
- `marked [human]`: the issue marks the AC with `[human]`
- `feel or look`: a subjective judgment (how it feels, whether it looks right);
  anything measurable, also visual, is tested by the playtester
- `device`: a real device or the Studio Device Emulator
- `gamepad`: controller input, which has no MCP tool
- `multiple clients`: several real clients at once

Everything else the playtester cannot test is ERROR: a missing or failing tool,
a step blocked by the hook, a missing Studio switch, a Studio state that does not
match the SHA, Studio or MCP not reachable.

## Accepting the report

Accept only a Pull Request comment starting with
`## Playtest (Agent) – <branch> @ <full SHA>` for exactly the handed-off SHA. It
must cover every AC with evidence, list Console errors and warnings and give the
Overall. Agents and humans post with the same GitHub account: only comments
with this heading count as agent reports; human results start with
`## Human check (<name>) @ <SHA>`. Screenshot descriptions are valid evidence
where `gh` cannot attach images; do not invent attachments or observations.

- **PASS:** the runtime ACs are satisfied for this SHA. Add every NEEDS HUMAN
  REVIEW AC to the milestone's END PLAYTEST list with
  [the end-playtest skill](../../end-playtest/SKILL.md) before
  READY_FOR_HUMAN_MERGE. These ACs do not block the Pull Request.
- **FAIL:** batch the findings with any other failures into the next correction
  round (SKILL.md section 5), in the same implementation worktree.
- **ERROR:** record BLOCKED with the cause. A testability gap, e.g. a missing
  Studio switch, is a review finding for the next correction round. Tool, MCP,
  hook or setup problems are fixed and the playtest is rerun; waiting for that
  uses no round. Never move an ERROR AC to the END PLAYTEST list yourself; only an
  owner may, recorded on the issue with name and reason.
- A NEEDS HUMAN REVIEW outside the five categories, or for something measurable,
  counts as ERROR: rerun with clearer hints.

Compare the tested SHA with the live Pull Request head; later commits need new
checks and a new playtest. A PASS for an earlier SHA does not approve later commits.

## Cleanup

The playtester stops Play and changes no checkout. The playtest worktree stays at
the tested SHA until the next setup moves it. If the report says the control
checkout was not clean or not on `main`, resolve that before the next Studio
handoff. Never use a destructive reset to clean up.

## Phase 2: the DM runs the playtest

Setup and handoff are designed so the DM can run them unchanged on the Studio
host: the playtester needs no checkout, no `rojo` and no interactive answer, uses
only Bash commands from the project allow list and the Studio MCP tools in its
definition, and ends with
`PLAYTEST RESULT: <PASS|FAIL|ERROR> · NEEDS HUMAN REVIEW: <n> · <comment URL or reason>`.
A headless launch must grant exactly those MCP tools, and the DM needs permission
for the setup commands (`git worktree`, opening and closing Studio). Where the
Studio host runs and how Studio is opened and closed there is decided with
Phase 2. Do not add steps that need a person between setup and report.

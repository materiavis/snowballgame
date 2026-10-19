# GitHub handoff and recovery

Use connected tools when they support the operation, or authenticated `gh`.
Derive the repository from the verified Git remote. The examples assume the DM
sets `build_repo` to that `owner/name`, and validates `build_issue` as a positive
issue number. Never execute interpolated issue text or arbitrary URLs as shell.

```bash
gh issue view "$build_issue" --repo "$build_repo" --comments
gh pr list --repo "$build_repo" --state all --limit 1000 \
  --json number,title,body,url,state,headRefName,baseRefName,headRefOid
git worktree list --porcelain
```

Inspect actual issue links/closing references and branch scope; a substring or
similar title alone is not identity. Paginate PRs and issue comments where needed
instead of assuming a finite CLI limit is complete. If a PR already merged,
confirm whether it closes this issue before treating implementation as complete.

## Durable progress on the issue

The **issue discussion** is the canonical build-loop ledger, including before a
PR exists. Read all matching records and linked PR reports on every resume. Use
one marker for this issue:

```markdown
<!-- build-loop:v1 issue=42 -->
## Build-loop progress
- State: IMPLEMENTING
- Correction round: 0 / 3 (0 = initial implementation)
- Base: main
- Branch / worktree: <actual values>
- PR / full head SHA: <actual values, or not yet available>
- Agent / session: <actual agent and resumable identifier, if available>
- Findings and evidence: <AC IDs, command results or report links>
- Next action: <concrete next step>
```

Replace example 42 with the actual issue number. Append transitions with
`gh issue comment "$build_issue" --repo "$build_repo" --body-file <file>`.
Write real newlines into a temporary file with a file-writing tool or a safely
quoted heredoc; do not embed report text into shell arguments. Supported states:
IMPLEMENTING, CHECKING, WAITING_FOR_PLAYTEST, CORRECTING, BLOCKED, NEEDS_OWNER,
READY_FOR_HUMAN_MERGE, MERGED. Record outcomes and partial failure honestly.

The highest recorded **started** correction round is consumed even if a session
was interrupted. Reconstruct from agent/PR history when necessary; missing logs
are not evidence of round 0. A NEEDS_OWNER transition cannot be cleared by merely
rerunning `/build`. An owner-authorized new budget needs a linked decision and a
new clearly identified cycle preserving the old rounds, not a silent reset.

Record the initial assignment before delegating. When a correction is needed,
persist CORRECTING and the incremented number **before** dispatch, then record
CHECKING with its resulting SHA. An interrupted CORRECTING state means inspect
and continue that attempt; never launch a duplicate agent to spend the same
round again. Persist transitions needed for recovery; routine tool calls need no
individual comments. If GitHub writes fail, return the exact recovery handoff
and stop before additional delegation or merge.

## PR creation and evidence

Fill the existing PR template and write it to a temporary body file. Choose the
actual base explicitly; use a draft when checks or testing remain pending.

```bash
gh pr create --repo "$build_repo" --base "$build_base" \
  --head "$build_branch" --title "$build_title" --body-file /tmp/build-pr.md
gh pr view "$build_pr" --repo "$build_repo" \
  --json number,url,state,isDraft,headRefName,headRefOid,baseRefName,mergeable,reviewDecision,statusCheckRollup
gh pr diff "$build_pr" --repo "$build_repo"
```

For an integration branch, `Closes #<issue>` may not close the issue until a later
merge to the default branch. Report the actual issue state, never assume closure.
Use PR comments for the DM's AC coverage and playtester report, each tied to a
full SHA. Keep technical PASS, runtime PASS and pending checks distinguishable.

## Merge

The live `baseRefName` controls permission. `main` is always human-only, including
auto-merge. For another approved base, first pass section 6 of the skill; with
an appropriate repository-supported merge method, bind the verified SHA:

```bash
gh pr merge "$build_pr" --repo "$build_repo" --merge \
  --match-head-commit "$build_head"
gh pr view "$build_pr" --repo "$build_repo" \
  --json state,mergedAt,mergeCommit,baseRefName,headRefOid,url
```

Do not run this for `main`, with `--admin`, or with pending checks. Inspect the
operation result and live merged state; a submitted merge command is not proof
of a merge. Preserve the configured `gh pr merge` permission prompt rather than
adding blanket allowances to settings.

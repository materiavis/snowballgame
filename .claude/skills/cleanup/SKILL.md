---
name: cleanup
description: Delete branches and agent worktrees the Development Manager no longer needs, at the right time, and record every deletion on the Pull Request so owners can review and restore it. Use after a merge (from /report), after a milestone's END PLAYTEST is closed (from /end-playtest), or as /cleanup for a sweep of all branches.
---

# Branch cleanup

Act as Development Manager in this repository.
Invocation: `/cleanup [<PR number or URL> | <milestone title or number>]`.
Arguments: $ARGUMENTS
With a PR, handle its branch; with a milestone, the branches of its PRs; without
an argument, sweep all branches and worktrees. You delete the branches yourself,
not a GitHub setting. Owners review the timing in the record on each Pull
Request and can restore a branch from there.

## 1. When a branch is due

Only issue branches you created, `feat|fix|chore|docs/<issue>-<slug>`, whose PR
is **merged**. Verify on GitHub with
`gh pr view <pr> --json state,mergedAt,mergeCommit,headRefName,headRefOid`, and
after `git fetch origin` that the branch tip (local and `origin/<branch>`) equals
the merged head SHA. A branch with commits after the merge is not due: keep it
and report it.

- **Directly after the merge** when no acceptance criterion of the PR waits for
  the END PLAYTEST: every AC is PASS or DM CHECK in the accepted playtest, or
  Studio was not applicable.
- **After the END PLAYTEST** when at least one AC of the PR is on the milestone's
  END PLAYTEST list: keep the branch until that issue is closed with every item
  PASS, then delete it.
- **PR closed without merge:** only after an owner wrote
  `Owner decision: delete branch` on the PR.

The agent worktree is removed directly after the merge in every case; the branch
keeps all commits.

Never delete `main`, branches of open PRs, unmerged commits, branches you did not
create (e.g. `test/…`, integration branches) or the playtest worktree. List them
for the owners instead. `.claude/hooks/guard-git-cleanup.sh` blocks every other
form of deletion; if it blocks you, report the message instead of working around it.

## 2. Procedure per branch

1. **Worktree:** `git worktree list`. If the branch is checked out in an agent
   worktree, `git worktree remove .claude/worktrees/<name>`. Never `--force`; if
   Git refuses because of uncommitted changes, keep it and report.
2. **Branch, when due:** `git branch -d <branch>`, then
   `git push origin --delete <branch>`, one branch per command. Never `-D`; if Git
   refuses, keep the branch and report.
3. `git fetch --prune` and `git worktree prune`.
4. **Record** on the PR with `gh pr comment <pr> --body-file -`, once per change
   of state, not on every run:

```markdown
## Branch cleanup
- Branch: `<branch>` @ `<full SHA>`: deleted locally and on GitHub · Worktree: `<path>` removed
- Reason: merged in `<merge SHA>`, no AC waits for the END PLAYTEST
- Restore: "Restore branch" on this Pull Request, or `git push origin <full SHA>:refs/heads/<branch>`
```

   Other reasons: `END PLAYTEST #<n> closed with every item PASS` or
   `Owner decision: delete branch by <owner> on <date>`. When the branch is kept:
   `Branch: <branch> @ <full SHA>: kept until END PLAYTEST #<n> is closed (pending: AC…)`
   with the removed worktree.

## 3. Sweep and milestone runs

List local branches, remote branches (`git branch -r` after `git fetch --prune`),
worktrees and the PRs behind them. Decide per section 1, delete what is due with
section 2, keep the rest. A milestone run looks only at the PRs of that
milestone, typically after its END PLAYTEST issue was closed.

Return a table: branch, PR, state, action (`deleted`, `kept`, `listed for
owners`) and reason, plus anything Git or the hook refused.

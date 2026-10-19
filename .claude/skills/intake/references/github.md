# GitHub creation and recovery

Read this only after the concept and both plan approvals pass. The examples use
Git Bash and the GitHub CLI; connected GitHub tools are equally valid if they
support the required operations. Missing milestone-write support is a concrete
access gap, not permission to omit milestones or bypass authentication.

Resolve `intake_repo` from the verified Git remote, matching section 0 of the
concept. Keep the same repository throughout the run.

```bash
gh api --paginate "repos/$intake_repo/milestones?state=all&per_page=100"
gh issue list --repo "$intake_repo" --state all --limit 1000 \
  --json number,title,body,url,state,milestone
```

The issue limit is illustrative; use paginated REST listing if more results
exist. REST issue listings also contain PRs: distinguish those from issues while
still checking whether an existing PR implements a feature.

Use the concept page ID (canonical UUID without URL query parameters) and the
stable feature key from the approved plan to identify issues, for example:

```html
<!-- intake:concept=PAGE_ID;feature=7.1-ball-growth -->
```

Search returned issue bodies for the marker; do not rely solely on titles or
indexed search. Also check older unmarked issues by concept link, section and
scope. Reuse genuine matches, record them in the ADR and preserve their history.
If a match is ambiguous, resolve it before creating a duplicate. Closed issues
are still matches; do not reopen them automatically. Flag changed requirements
for plan review instead of silently replacing issue bodies or completed work.

Create only missing milestones, then missing issues. Example commands:

```bash
gh api --method POST "repos/$intake_repo/milestones" \
  --input /tmp/intake-milestone.json
gh issue create --repo "$intake_repo" --title "$intake_title" \
  --body-file /tmp/intake-feature.md --milestone "$intake_milestone"
```

Generate the JSON request with a serializer, including `title`, `description`
and an optional ISO `due_on` for an actual known date. Do not invent a timezone
when a concept specifies only a calendar date; preserve the date in the
description if no convention is established. Omit `--milestone` for later
features without an approved roadmap milestone. Use UTF-8 body files with actual
newlines; never interpolate source text into shell commands. Do not use `eval`.
Add existing labels only when applicable.

Keep milestone numbers and issue URLs returned by successful writes in the ADR
log. Re-read each created object before the next dependent operation. Add issue
dependency links after the referenced issues exist, preserving unrelated text.
If any write fails or times out, stop further creation, re-list the affected
objects, and reconcile the outcome. Retry only confirmed missing work after
resolving the error; do not retry an unchanged permission failure repeatedly.
Resume from the result log and current GitHub state, not from an assumed empty
repository. Finish by comparing every coverage row against its actual issue.

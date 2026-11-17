---
name: pr-chain-verify
description: "Add a per-PR verification document to every PR in a PR chain as its own commit, using a cascade rebase from the root PR to the leaf PR with backups and pinned leases, then check chain integrity (ancestry, PR bases, file presence). Use when each PR in a chain needs a committed record that it was verified. Triggers: PR チェーン検証, テスト結果を PR ごとに commit."
---

# PR Chain Verify

Add a markdown file as a separate commit to each PR in a PR chain, as a record that the PR's behavior was verified. The work involves a cascade rebase from the root (the PR directly on the base branch) to the leaf (the top PR).

Requirements: `git` 2.38 or later (for `--no-update-refs`), `gh` (authenticated).

## Prerequisites

- The user has given the list of target PRs and what was verified (or the results can be assembled from an existing results file)
- The parent/child relationships of the PR chain are known
- The repository's convention for where verification documents live has been checked (for example `docs/test-results/<slug>.md`; it may differ by repository)

## Workflow

Run the commands of each step in one shell session, and use branch names without an `origin/` prefix.

### 1. Check the convention

Check the existing directory and naming convention.

```bash
ls docs/test-results/ 2>&1 | head -10
head -20 docs/test-results/<sample>.md
```

If nothing is found, ask the user where to put the files. Names are usually a short slug rather than the PR number (for example `feature-a.md`, `feature-b.md`).

Fix the verification file path of every PR here (`<vfile>` below); steps 5 to 7 use exactly that path.

### 2. Organize the PR list

```bash
for pr in <PR number list>; do
  gh pr view "$pr" --repo <owner/repo> --json number,title,baseRefName,headRefName,author \
    --template '#{{.number}} | base={{.baseRefName}} | head={{.headRefName}}{{"\n"}}'
done
```

Order the chain from root to leaf. Handle independent PRs (based on the default branch, etc.) afterwards.

### 3. File template

Fill in only what was observed. A row that was not run says `not run`, never a pass. Before the push `gh pr checks` still reports the old head, so the CI row is `not run` unless the rebased head was pushed and CI finished on it.

```markdown
# Test result: #<PR number> <PR title>

- **Test date**: <YYYY-MM-DD>
- **Environment**: <env>
- **Method**: <outline of the means used>

## Test items

| # | Test | Means | Expected | Result |
|---|------|-------|----------|--------|
| 1 | CI jobs on the rebased PR head | `gh pr checks <num>` | All pass | <pass / fail, only after the rebased head was pushed and CI ran on it; `not run` otherwise> |
| 2 | <specific item> | <command/means> | <expected> | <pass / fail / not run> |

## Notes

<Additional notes; state any items that were not run>
```

### 4. Pre-flight and backup

Before anything is rewritten. The loop covers every branch that gets a commit: the chain and the independent PRs of step 6.

```bash
# Stop and ask the user if this prints STOP
git fetch origin || echo "STOP: fetch failed"
# Any output from the next line is a stop condition (uncommitted work would be lost by the reset below): ask the user
git status --porcelain

BASE=<base branch of the root PR>
for BR in <every branch that gets a commit>; do
  # Local commits that were never pushed would be discarded by the reset below: stop and ask
  if git rev-parse -q --verify "refs/heads/${BR}" >/dev/null && [ -n "$(git rev-list "origin/${BR}..${BR}")" ]; then
    echo "UNPUSHED commits on ${BR}: stop and ask"
  fi
  # Original tips: the rollback source, the lease value and the old parent for the next rung
  # An existing backup is an earlier rollback point: stop and ask the user instead of overwriting it
  git branch --no-track "backup/${BR}" "origin/${BR}" || echo "STOP: backup/${BR} exists or cannot be created"
done
```

### 5. Commit to each PR in the chain (root -> leaf)

Start from the root and go up one rung at a time. Each rung is rebased onto its parent's new tip, so the commit added to a parent reaches every PR above it. For each PR:

```bash
BR="<branch-name>"
PARENT_BR="<parent-branch-name>"  # for the root PR: the base branch ($BASE)
VFILE="<vfile>"                   # the path fixed in step 1

# Each line is one chain: it stops at the first failing command, so the reset never runs on the wrong branch.
# Safe only because step 4 found no uncommitted or unpushed work. Run exactly one of the two lines.
# Root PR: pick up the latest base
git switch "$BR" && git reset --hard "origin/${BR}" && git rebase --no-update-refs "origin/${PARENT_BR}"
# Every other PR: replay only its own commits onto the parent's new tip; the parent's original tip marks where they start
git switch "$BR" && git reset --hard "origin/${BR}" && git rebase --no-update-refs --onto "origin/${PARENT_BR}" "$(git rev-parse "backup/${PARENT_BR}")" "$BR"

# If the chain above failed, stop here. Otherwise <write the verification file to "$VFILE">, then:
git add "$VFILE" && git commit -m "docs(test-results): add verification record for #<num> <short-title>" \
  && git push --force-with-lease="refs/heads/${BR}:$(git rev-parse "backup/${BR}")" origin "$BR" \
  && git update-ref "refs/pushed/${BR}" "$(git rev-parse "$BR")"   # the pushed tip is the rollback lease
```

If `git rebase` stops on a conflict, stop the cascade: resolve it as described under "Handling conflicts" in the pr-chain-reorder-head skill (`git diff --check`, `git add`, `git rebase --continue`), or run `git rebase --abort` and ask the user. Nothing has been pushed for that rung yet.

If different people own different rungs, use the owner-aware procedure in pr-chain-reorder-head instead of pushing every rung yourself.

### 6. Commit to independent PRs (default-branch-based / independent release branches)

No cascade rebase is needed, but these branches go through the step 4 pre-flight and backup like the chain branches (a plain push would also carry unpushed local commits into the PR). Then, for each one:

```bash
BR="<branch-name>"
VFILE="<vfile>"

git switch "$BR" && git reset --hard "origin/${BR}"
# If the line above failed, stop here. Otherwise <write the verification file to "$VFILE">, then:
git add "$VFILE" && git commit -m "docs(test-results): add verification record for #<num> <short-title>" \
  && git push origin "$BR" && git update-ref "refs/pushed/${BR}" "$(git rev-parse "$BR")"
```

### 7. Verify chain integrity

After all commits are done, give one row per PR: `<PR number> <branch> <expected parent branch> <verification file path>`.

```bash
git fetch origin || echo "STOP: fetch failed, the checks below would read stale refs"
while read -r pr br parent vfile; do
  parent=${parent#origin/}
  git merge-base --is-ancestor "origin/${parent}" "origin/${br}" || echo "NOT STACKED: ${br} is missing ${parent}"
  [ "$(gh pr view "$pr" --repo <owner/repo> --json baseRefName --jq .baseRefName)" = "$parent" ] || echo "WRONG PR BASE: #${pr} should target ${parent}"
  git cat-file -e "origin/${br}:${vfile}" || echo "MISSING FILE: ${vfile} on ${br}"
  [ "$(git cat-file -s "origin/${br}:${vfile}")" -gt 0 ] || echo "EMPTY FILE: ${vfile} on ${br}"
  git show "origin/${br}:${vfile}" | grep -qF "#${pr}" || echo "FILE DOES NOT MENTION #${pr}: ${vfile} on ${br}"
  # The file must be added by this branch's own commits, not inherited from a parent
  [ -n "$(git diff --name-only --diff-filter=A "origin/${parent}...origin/${br}" -- "$vfile")" ] || echo "FILE NOT ADDED BY ${br}: ${vfile}"
  gh pr view "$pr" --repo <owner/repo> --json number,mergeable,mergeStateStatus \
    --template '#{{.number}} {{.mergeable}}/{{.mergeStateStatus}}{{"\n"}}'
done <<'EOF'
<PR number> <branch> <parent> <verification file path>
EOF
```

No `STOP` / `NOT STACKED` / `WRONG PR BASE` / `MISSING FILE` / `EMPTY FILE` / `FILE DOES NOT MENTION` / `FILE NOT ADDED BY` line means the chain is intact. To undo, restore each branch, remote and local, from its `backup/<branch>` as in the Rolling back section of pr-chain-reorder-head (its lease is the `refs/pushed/<branch>` ref recorded above); skip its `gh pr edit` line, because this skill does not change PR bases.

## Output

When the work is done, report to the user:

- The list of files created (PR number / file path / commit SHA)
- The chain integrity check result
- The mergeable state

---
name: pr-chain-verify
description: "Add a per-PR verification document to every PR in a PR chain as its own commit, using a cascade rebase from the root PR to the leaf PR, and check chain integrity afterwards. Use when each PR in a chain needs a committed record that it was verified. Triggers: verify PR chain, per-PR test results commit, PR チェーン検証, テスト結果 PR ごと commit."
---

# PR Chain Verify

Add a markdown file as a separate commit to each PR in a PR chain, as a record that the PR's behavior was verified. The work involves a cascade rebase from the root to the leaf.

## Prerequisites

- The user has given the list of target PRs and what was verified (or the results can be assembled from an existing results file)
- The parent/child relationships of the PR chain are known
- The repository's convention for where verification documents live has been checked (for example `docs/test-results/<slug>.md`; it may differ by repository)

## Workflow

### 1. Check the convention

Check the existing directory and naming convention.

```bash
ls docs/test-results/ 2>&1 | head -10
head -20 docs/test-results/<sample>.md
```

If nothing is found, ask the user where to put the files. Names are usually a short slug rather than the PR number (for example `retry-backoff.md`, `rate-limit-verification.md`).

### 2. Organize the PR list

```bash
for pr in <PR number list>; do
  gh pr view $pr --repo <owner/repo> --json number,title,baseRefName,headRefName,author \
    --template '#{{.number}} | base={{.baseRefName}} | head={{.headRefName}}{{"\n"}}'
done
```

Order the chain from root to leaf. Handle independent PRs (based on main, etc.) afterwards.

### 3. File template

```markdown
# Test result: #<PR number> <PR title>

- **Test date**: <YYYY-MM-DD>
- **Environment**: <env>
- **Method**: <outline of the means used>

## Test items

| # | Test | Means | Expected | Result |
|---|------|-------|----------|--------|
| 1 | All CI jobs pass | `gh pr checks <num>` | All pass | ✅ pass |
| 2 | <specific item> | <command/means> | <expected> | ✅/⚠️/❌ |

## Notes

<Additional notes; state any items that were not run>
```

### 4. Commit to each PR in the chain (root -> leaf)

Start from the root. For each PR, do these 5 steps:

```bash
BR="<branch-name>"
PARENT_BR="<parent-branch-name>"  # for a root branch such as release/v1.0 the parent is the base branch

git switch "$BR"
git reset --hard "origin/$BR"              # align with the latest origin
git rebase "$PARENT_BR"                    # pick up the parent's latest commit (for the root branch, `origin/<base>`)
# <write the verification file>
git add docs/test-results/<slug>.md
git commit -m "docs(test-results): add verification record for #<num> <short-title>"
git push --force-with-lease origin "$BR"
```

Important: after committing to the root PR, the child PRs must be rebased onto the new root. Cascade this to the end of the chain.

### 5. Commit to independent PRs (main-based / independent release branches)

No cascade rebase is needed. Switch to the branch, commit, push.

### 6. Verify chain integrity

After all commits are done:

```bash
# Check each parent/child relationship with merge-base --is-ancestor
for pair in "<parent> <child>" ...; do
  parent=$(echo $pair | awk '{print $1}')
  child=$(echo $pair | awk '{print $2}')
  if git merge-base --is-ancestor "origin/$parent" "origin/$child"; then
    echo "✅ $child"
  else
    echo "❌ $child missing $parent"
  fi
done

# Check the mergeable state of every PR
for pr in <list>; do
  gh pr view $pr --repo <r> --json number,mergeable,mergeStateStatus \
    --template '#{{.number}} {{.mergeable}}/{{.mergeStateStatus}}{{"\n"}}'
done
```

## Notes and lessons

- Always push with `--force-with-lease`
- Committing to one middle PR of the chain propagates a rebase to everything downstream. Processing in a batch makes mistakes less likely
- Once a commit lands on a middle PR, origin is updated too. Rebase child PRs with `git rebase origin/<parent>`, not `git rebase <local parent branch>`, to avoid connecting to the wrong base
- In repositories with GitHub auto-rebase enabled, GitHub may automatically rebase the child PRs after the parent PR is pushed. In that case, fetch origin and align the local branches
- Criterion for splitting verification files per PR: the granularity at which looking at that file alone is enough to vouch for the PR's behavior

## Output

When the work is done, report to the user:

- The list of files created (PR number / file path / commit SHA)
- The chain integrity check result
- The mergeable state

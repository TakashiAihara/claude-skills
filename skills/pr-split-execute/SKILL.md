---
name: pr-split-execute
description: "Execute a PR split: back up the branch, create the split branches, and open a chain of feature-to-feature PRs, then explain the merge order. Use after the pr-split-analyze skill has produced an approved split plan. Triggers: pr split execute, execute the split, 分割実行."
---

# PR Split Execute

Split a branch according to the plan decided with the pr-split-analyze skill, and create a feature -> feature chain of PRs.

## Prerequisites

- The split plan has been decided with the pr-split-analyze skill
- The user has approved it

## Workflow

### 1. Back up the current branch

```bash
CURRENT=$(git branch --show-current)
BACKUP="${CURRENT}-backup-$(date +%Y%m%d%H%M%S)"
git switch -c "$BACKUP"
git switch "$CURRENT"
echo "Backup created: $BACKUP"
```

### 2. Close the existing PR, if there is one

```bash
# Check for an existing PR
gh pr view --json number,url 2>/dev/null
# If there is one, close it (it is being split)
gh pr close <number> --comment "Splitting this PR. It will be re-created as split PRs."
```

Confirm with the user before closing it.

### 3. Create the split branches

Following the split plan, create the branches in order starting from the base branch.

```bash
BASE_BRANCH=develop  # or main

# Branch for PR 1
git switch -c "${CURRENT}-part1" "$BASE_BRANCH"
# Bring in the target commits/files with cherry-pick or checkout
git cherry-pick <commit-hash>...
# or bring them in file by file
git checkout "$CURRENT" -- <file1> <file2> ...

# Branch for PR 2 (based on PR 1)
git switch -c "${CURRENT}-part2" "${CURRENT}-part1"
git checkout "$CURRENT" -- <file3> <file4> ...

# Branch for PR 3 (based on PR 2)
# ...
```

### 4. Create a PR on each branch

Create the PRs in dependency order:

```bash
# PR 1: develop <- part1
git switch "${CURRENT}-part1"
git push -u origin "${CURRENT}-part1"
gh pr create --base develop --draft \
  --title "feat: <Part 1 title>" \
  --body "Part 1 of PR split from #<original>. ..."

# PR 2: part1 <- part2
git switch "${CURRENT}-part2"
git push -u origin "${CURRENT}-part2"
gh pr create --base "${CURRENT}-part1" --draft \
  --title "feat: <Part 2 title>" \
  --body "Part 2 of PR split. Depends on #<part1-number>. ..."
```

### 5. Request a CodeRabbit review on each PR

If the repository uses CodeRabbit:

```bash
gh pr comment <number> --body "@coderabbitai full review"
```

### 6. Explain the merge order

Tell the user:

```text
## Merge order

1. Merge PR #<part1>
2. Change PR #<part2>'s base to develop (`gh pr edit <number> --base develop`)
3. Merge PR #<part2>
4. (Repeat for the rest)
```

## Choosing a splitting method

| Method | When to use it |
|------|----------|
| `cherry-pick` | The commits are cleanly separated by responsibility |
| `checkout -- <files>` | The split can be made file by file (infrastructure / app / test) |
| Manual editing | A single file has to be split (avoid this) |

## Notes

- Keep the backup branch for a while after the split is done
- Check that each PR is 2000 lines or fewer with `git diff --stat`
- Write the original PR number in the description of every split PR
- Deleting the backup branch after the split is left to the user

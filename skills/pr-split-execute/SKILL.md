---
name: pr-split-execute
description: "Execute a PR split: back up the branch, build a chain of part branches that together equal the original, open a feature-to-feature chain of draft PRs, and explain the merge order including the rebase each part needs after its parent is squash-merged. Use after the pr-split-analyze skill has produced an approved split plan. Triggers: PR 分割実行, 分割を実行."
---

# PR Split Execute

Split a branch according to the plan decided with the pr-split-analyze skill, and create a feature -> feature chain of PRs.

Requirements: `git`, `gh` (authenticated). Size targets live in the pr-split-analyze skill; they are not repeated here.

## Prerequisites

- The split plan has been decided with the pr-split-analyze skill
- The user has approved it

## Workflow

Variables (`CURRENT`, `BASE_BRANCH`) are reused across steps. Run all commands in one shell session, or set them again at the top of each block.

### 1. Pre-flight and backup

```bash
CURRENT=$(git branch --show-current)
# Base: the PR's base if there is a PR, otherwise the remote default branch
BASE_BRANCH=$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null) || BASE_BRANCH=
[ -n "$BASE_BRANCH" ] || BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
git fetch origin "$BASE_BRANCH"

# The working tree must be clean; stop and ask the user if this prints anything
git status --porcelain

# Backup of the branch being split
git branch --no-track "backup/${CURRENT}-$(date +%Y%m%d%H%M%S)" "$CURRENT"
```

### 2. Create the part branches

Following the split plan, create the branches in order. Part 1 starts from the remote base; every later part starts from the previous part. Commit in each part before creating the next branch.

```bash
git switch --no-track -c "${CURRENT}-part1" "origin/$BASE_BRANCH"

# Bring in the part's files in their final state. `git restore --source` also carries deletions
# (a path missing from "$CURRENT" is removed). For a rename, list both the old and the new path.
git restore --source "$CURRENT" --staged --worktree -- <path1> <path2> ...
# A file that is split across parts: pick only this part's hunks
git restore -p --source "$CURRENT" --staged --worktree -- <file>
# Or, when commits are cleanly separated by responsibility, cherry-pick them instead (they are already commits: skip the commit below)
git cherry-pick <commit-hash>...

git commit -m "feat: <Part 1 title>"

# Part 2 (based on part 1), same procedure
git switch -c "${CURRENT}-part2" "${CURRENT}-part1"
git restore --source "$CURRENT" --staged --worktree -- <path3> <path4> ...
git commit -m "feat: <Part 2 title>"

# Part 3 (based on part 2), and so on
```

### 3. Verify the parts

```bash
# Integrity: the last part must equal the original branch; any output means something was lost or added
git diff --stat "$CURRENT" "${CURRENT}-part<N>"

# Each part must build and pass its tests on its own: check out each part and run the repository's build and test commands
git switch "${CURRENT}-part1"
```

### 4. Push and create a PR for each part

Create the PRs in dependency order, then record every part's tip as a backup ref (the merge order below needs the original tips; refresh a part's backup whenever you push new commits to it).

```bash
# Part 1: base <- part1
git push -u origin "${CURRENT}-part1"
gh pr create --head "${CURRENT}-part1" --base "$BASE_BRANCH" --draft \
  --title "feat: <Part 1 title>" \
  --body "Part 1 of the split of #<original>. ..."

# Part 2: part1 <- part2
git push -u origin "${CURRENT}-part2"
gh pr create --head "${CURRENT}-part2" --base "${CURRENT}-part1" --draft \
  --title "feat: <Part 2 title>" \
  --body "Part 2 of the split of #<original>. Depends on #<part1-number>. ..."

for i in 1 2 3; do git branch --no-track -f "backup/${CURRENT}-part${i}" "${CURRENT}-part${i}"; done
```

If the repository uses an automated reviewer such as CodeRabbit, trigger it here the way the repository documents (for example `gh pr comment <number> --body "@coderabbitai full review"`).

### 5. Close the original PR

Only after every split PR exists. Confirm with the user before running it.

```bash
gh pr close <original-number> --comment "Split into #<part1>, #<part2>, ... "
```

### 6. Explain the merge order

If a part is squash-merged, the next part's branch still contains the original commits of the previous part, so merging it as is re-shows or conflicts with them. Tell the user to merge PR #<part1> first, then, for each following part in order, run this block after the previous part is merged (shown for part 2 after part 1; for part 3 use `PREV=${CURRENT}-part2` and `NEXT=${CURRENT}-part3`). Do not refresh the backup refs during this sequence: the old tip of each part is what the next rebase starts after.

```bash
PREV="${CURRENT}-part1"; NEXT="${CURRENT}-part2"
git fetch origin
git switch "$NEXT"
# Replay only NEXT's own commits onto the base (the old tip of PREV marks where they start)
git rebase --onto "origin/$BASE_BRANCH" "$(git rev-parse "backup/${PREV}")" "$NEXT"
# Retarget first, then push; the lease is pinned to NEXT's tip as it was before the rebase
gh pr edit <NEXT-pr-number> --base "$BASE_BRANCH"
git push --force-with-lease="refs/heads/${NEXT}:$(git rev-parse "backup/${NEXT}")" origin "$NEXT"
```

If the rebase stops on a conflict, resolve it or run `git rebase --abort` and ask the user. Merge PR #<part2> once its checks pass, then repeat for the next part.

## Choosing a splitting method

| Method | When to use it |
|------|----------|
| `git restore --source "$CURRENT" -- <paths>` | The split can be made file by file (infrastructure / app / test); also carries deletions |
| `git restore -p --source "$CURRENT" -- <file>` | A single file has to be split across parts |
| `cherry-pick` | The commits are cleanly separated by responsibility |

## Notes

- Keep the backup refs until the whole chain is merged; deleting them is left to the user
- Write the original PR number in the description of every split PR

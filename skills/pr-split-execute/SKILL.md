---
name: pr-split-execute
description: "Execute a PR split: back up the branch, build a chain of part branches that together equal the original, open a feature-to-feature chain of draft PRs, and explain the merge order including the rebase each part needs after its parent is squash-merged. Use after the pr-split-analyze skill has produced an approved split plan. Triggers: PR 分割実行, 分割を実行."
---

# PR Split Execute

Split a branch according to the plan decided with the pr-split-analyze skill, and create a feature -> feature chain of PRs.

Requirements: `git` 2.38 or later (for `--no-update-refs`), `gh` (authenticated). Size targets live in the pr-split-analyze skill; they are not repeated here.

## Prerequisites

- The split plan has been decided with the pr-split-analyze skill
- The user has approved it

## Workflow

Variables (`CURRENT`, `BASE_BRANCH`, `SRC`, `PARTS`) are reused across steps. Run all commands in one shell session, or set them again at the top of each block.

### 1. Pre-flight and backup

```bash
CURRENT=$(git branch --show-current)
# Base: the PR's base if there is a PR, otherwise the remote default branch
BASE_BRANCH=$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null) || BASE_BRANCH=
[ -n "$BASE_BRANCH" ] || BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
# Stop and ask the user if this prints STOP: detached HEAD, the base is unknown or cannot be fetched
[ -n "$CURRENT" ] && [ -n "$BASE_BRANCH" ] && git fetch origin || echo "STOP: detached HEAD, base branch empty or fetch failed"

# The working tree must be clean; stop and ask the user if this prints anything
git status --porcelain

# Merge commits in the range the rebase below would rewrite: any output is a stop condition (the rebase would flatten them)
git rev-list --merges "origin/$BASE_BRANCH..$CURRENT"

# Backup of the branch being split
git branch --no-track "backup/${CURRENT}-$(date +%Y%m%d%H%M%S)" "$CURRENT"

# The branch the parts are cut from. If the base advanced after CURRENT was cut, restoring files from CURRENT
# would revert the base's newer changes, so split a copy that is rebased onto the current base instead
SRC="$CURRENT"
if ! git merge-base --is-ancestor "origin/$BASE_BRANCH" "$CURRENT"; then
  SRC="${CURRENT}-rebased"
  git switch --no-track -c "$SRC" "$CURRENT" && git rebase --no-update-refs "origin/$BASE_BRANCH" || echo "STOP: rebase of the copy failed: run git rebase --abort and ask the user"
fi
```

If that rebase stops on a conflict, resolve it and run `git rebase --continue`: nothing else of this step is left, so go on to step 2.

When `SRC` is the rebased copy, tell the user: the parts carry the original change on top of the current base, not the original branch as it was.

### 2. Create the part branches

Following the split plan, create the branches in order. Part 1 starts from the remote base; every later part starts from the previous part. Commit in each part before creating the next branch. `<type>` is the conventional-commit type of that part's change (`feat`, `fix`, `refactor`, `docs`, `test`, ...).

```bash
git switch --no-track -c "${CURRENT}-part1" "origin/$BASE_BRANCH"

# Bring in the part's files in their final state from "$SRC"
git restore --source "$SRC" --staged --worktree -- <path1> <path2> ...
# Deleted files: remove them explicitly. For a rename, restore the new path above and remove the old path here
git rm -- <deleted-path1> <old-path-of-a-rename> ...
# A file that is split across parts: pick only this part's hunks
git restore -p --source "$SRC" --staged --worktree -- <file>
# Or, when commits are cleanly separated by responsibility, cherry-pick them instead (they are already commits: skip the commit below)
git cherry-pick <commit-hash>...   # hashes from `git log "origin/$BASE_BRANCH..$SRC"`

git commit -m "<type>: <Part 1 title>"

# Part 2 (based on part 1), same procedure
git switch -c "${CURRENT}-part2" "${CURRENT}-part1"
git restore --source "$SRC" --staged --worktree -- <path3> <path4> ...
git commit -m "<type>: <Part 2 title>"

# Part 3 (based on part 2), and so on
```

### 3. Verify the parts

```bash
PARTS=(1 2 3)   # one entry per part of the plan
prev="origin/$BASE_BRANCH"
for i in "${PARTS[@]}"; do
  # Scope: only this part's planned files may appear here
  echo "== part ${i} vs ${prev}"; git diff --stat "$prev" "${CURRENT}-part${i}"
  prev="${CURRENT}-part${i}"
done
# Integrity: the last part must equal the source; any output or a non-zero exit means something was lost or added
git diff --stat --exit-code "$SRC" "$prev" && echo "parts equal the source"
```

Compare the per-part output with the plan. Then check each part builds and passes its tests on its own: check out each part and run the repository's build and test commands.

### 4. Push and create a PR for each part

First record every part's tip as a backup ref (the merge order below needs the original tips), then create the PRs in dependency order. If the original branch has a PR, start each body with `Part N of the split of #<original>`; otherwise name the source branch there.

```bash
# One backup per part. If a backup already exists, stop and ask the user: do not overwrite it
for i in "${PARTS[@]}"; do
  git branch --no-track "backup/${CURRENT}-part${i}" "${CURRENT}-part${i}" || echo "STOP: backup/${CURRENT}-part${i} exists or cannot be created"
done

# Part 1: base <- part1
# Each push and its gh pr create form one chain: a rejected push must not open a PR for a stale remote branch
git push -u origin "${CURRENT}-part1" \
  && gh pr create --head "${CURRENT}-part1" --base "$BASE_BRANCH" --draft \
  --title "<type>: <Part 1 title>" \
  --body "Part 1 of the split of #<original>. ..."

# Part 2: part1 <- part2
git push -u origin "${CURRENT}-part2" \
  && gh pr create --head "${CURRENT}-part2" --base "${CURRENT}-part1" --draft \
  --title "<type>: <Part 2 title>" \
  --body "Part 2 of the split of #<original>. Depends on #<part1-number>. ..."

```

If a part gets new commits after its backup exists, delete that backup deliberately (with the user's agreement) and create it again from the new tip.

If the repository uses an automated reviewer such as CodeRabbit, trigger it here the way the repository documents (for example `gh pr comment <number> --body "@coderabbitai full review"`).

### 5. Close the original PR

Only if the original branch had a PR, and only after every split PR exists. Confirm with the user before running it.

```bash
gh pr close <original-number> --comment "Split into #<part1>, #<part2>, ... "
```

### 6. Explain the merge order

If a part is squash-merged, the next part's branch still contains the original commits of the previous part, so merging it as is re-shows or conflicts with them. Tell the user to merge PR #<part1> first, then, for each following part in order, run this block after the previous part is merged (shown for part 2 after part 1; for part 3 use `PREV=${CURRENT}-part2` and `NEXT=${CURRENT}-part3`). Do not refresh the backup refs during this sequence: the old tip of each part is what the next rebase starts after.

```bash
PREV="${CURRENT}-part1"; NEXT="${CURRENT}-part2"
# One chain: it stops at the first failing command. Replay only NEXT's own commits onto the base
# (the old tip of PREV marks where they start), retarget, then push; the lease is pinned to NEXT's tip as it was before the rebase
# refs/pushed/<NEXT> is recorded before the push (the rollback lease) and kept if the push fails: Rolling back decides from the remote's actual tip
git fetch origin \
  && git switch "$NEXT" \
  && git rebase --no-update-refs --onto "origin/$BASE_BRANCH" "$(git rev-parse "backup/${PREV}")" "$NEXT" \
  && gh pr edit <NEXT-pr-number> --base "$BASE_BRANCH" \
  && git update-ref "refs/pushed/${NEXT}" "$(git rev-parse "$NEXT")" \
  && git push --force-with-lease="refs/heads/${NEXT}:$(git rev-parse "backup/${NEXT}")" origin "$NEXT"
```

If the rebase stops on a conflict, resolve it or run `git rebase --abort` and ask the user. After `git rebase --continue` finishes the rebase, the part is not done: the chain stopped before the retarget, record and push. Run them now:

```bash
gh pr edit <NEXT-pr-number> --base "$BASE_BRANCH" \
  && git update-ref "refs/pushed/${NEXT}" "$(git rev-parse "$NEXT")" \
  && git push --force-with-lease="refs/heads/${NEXT}:$(git rev-parse "backup/${NEXT}")" origin "$NEXT"
```

Merge PR #<part2> once its checks pass, then repeat for the next part.

## Rolling back a part

Put one part back at its backup tip, remote and local, and its PR back on the previous part. The push is leased to the SHA recorded before the step 6 push (`refs/pushed/<part>`), not to `origin/<part>`, so a push by someone else afterwards is refused instead of overwritten. A part without that ref was never rebased or pushed by step 6: its remote is untouched and only the local branch is restored. If the step 6 push failed or was interrupted the ref can name a tip the remote never received, so the remote's actual tip decides (`git ls-remote origin refs/heads/<part>`): equal to `backup/<part>` means nothing was pushed (restore only the local branch), equal to `refs/pushed/<part>` means it was pushed (lease push, then restore), anything else means someone else moved it, so stop. The PR base is reverted only after the branch was restored.

```bash
# Any output from the next line is a stop condition (the reset below would discard it)
git status --porcelain
b="$NEXT"; cur=$(git branch --show-current)
ok=
p=$(git rev-parse -q --verify "refs/pushed/${b}") || p=
remote=$(git ls-remote origin "refs/heads/${b}" | cut -f1)
if [ -z "$p" ] || [ "$remote" = "$(git rev-parse "backup/${b}")" ]; then ok=1
elif [ "$remote" = "$p" ]; then git push --force-with-lease="refs/heads/${b}:${p}" origin "backup/${b}:refs/heads/${b}" && ok=1
fi
[ -n "$ok" ] \
  && if [ "$b" = "$cur" ]; then git reset --hard "backup/${b}"; else git branch -f "$b" "backup/${b}"; fi \
  && gh pr edit <NEXT-pr-number> --base "$PREV" \
  || echo "STOP: could not restore ${b}"
```

## Choosing a splitting method

| Method | When to use it |
|------|----------|
| `git restore --source "$SRC" -- <paths>` plus `git rm -- <deleted paths>` | The split can be made file by file (infrastructure / app / test) |
| `git restore -p --source "$SRC" -- <file>` | A single file has to be split across parts |
| `cherry-pick` | The commits are cleanly separated by responsibility |

## Notes

- Keep the backup refs and `refs/pushed/*` refs until the whole chain is merged; deleting them is left to the user
- If the original branch has a PR, write its number in the description of every split PR

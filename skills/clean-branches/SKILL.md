---
name: clean-branches
description: "Clean up local git branches that are already merged: prune remote-tracking refs, detect regular merges and squash merges against the fresh remote default branch, and delete only what the user approves. Use when local branches have piled up after PRs were merged. Requirements: git. Triggers: clean branches, delete merged branches, prune local branches, ブランチ掃除."
---

# Git Clean Branches

Tidy up the local branches of the current repo. Compare against `origin/<default>` after a fetch, never against a possibly stale local branch.

Run the commands of steps 1 to 4 in one shell, because `BASE` and `CANDIDATES` carry over.

## Steps

### 1. Fetch and detect the default branch

```bash
git fetch --prune origin || echo "fetch failed" >&2
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD) || echo "origin/HEAD is not set: run 'git remote set-head origin --auto' or ask the user for the default branch" >&2
BASE=${BASE#origin/}
echo "$BASE"
```

- Stop here if the fetch failed, if `BASE` is empty, or if `origin/$BASE` does not exist. A stale `origin/$BASE` can mark a branch as merged that the real remote never received, and never guess a default branch

### 2. Collect deletion candidates

Candidates exclude the current branch, the default branch, long-lived branches (`develop`, `release/*`), rollback refs (`backup/*`, which other skills of this plugin create and tell the user to keep), and branches checked out in another worktree.

Regular merges are branches whose tip is an ancestor of `origin/$BASE`. Squash merges rewrite history, so no commit of the branch exists in the base; instead build one synthetic commit holding the branch's whole tree on top of the merge-base and ask `git cherry` whether the base has a commit with the same patch-id:

```bash
CANDIDATES=$(mktemp)
CUR=$(git branch --show-current)
git for-each-ref --format='%(refname:short)' refs/heads | while read -r b; do
  case "$b" in "$CUR"|"$BASE"|develop|release/*|backup/*) continue ;; esac
  [ -z "$(git for-each-ref --format='%(worktreepath)' "refs/heads/$b")" ] || continue
  if git merge-base --is-ancestor "$b" "origin/$BASE"; then
    printf 'merged\t%s\t%s\n' "$b" "$(git rev-parse "$b")" >> "$CANDIDATES"
    continue
  fi
  mb=$(git merge-base "origin/$BASE" "$b") || { echo "skip $b: no merge-base" >&2; continue; }
  tmp=$(git -c user.name=x -c user.email=x@x commit-tree "$b^{tree}" -p "$mb" -m _) || { echo "skip $b: commit-tree failed" >&2; continue; }
  out=$(git cherry "origin/$BASE" "$tmp" "$mb") || { echo "skip $b: git cherry failed" >&2; continue; }
  [ -n "$out" ] || { echo "skip $b: empty cherry output" >&2; continue; }
  if ! printf '%s\n' "$out" | grep -q '^+'; then
    printf 'squash (content match)\t%s\t%s\n' "$b" "$(git rev-parse "$b")" >> "$CANDIDATES"
  fi
done
cat "$CANDIDATES"
```

- Columns are kind, branch, tip SHA
- The squash check only runs for branches that are ahead of the base (a branch that is not an ancestor always has at least one commit the base lacks)
- A `-` line from `git cherry` means the base already holds that exact patch, which is what a squash merge produces; a `+` line means it does not
- The squash match is by content only: a squash that was merged and later reverted on the base still matches. That is why the user approves the list, and why the tip SHA is printed for restoring
- A failed `git cherry` is never read as "merged": the branch is skipped and reported on stderr
- A squash commit that was edited on the way in (for example conflict resolution) has a different patch-id and is not detected. This fails safe: the branch stays

### 3. Get approval

- Show the user the list from `$CANDIDATES` (kind, branch, SHA) and wait for confirmation
- If the user drops entries, delete those lines from the file. Delete exactly what was approved and do not re-query at delete time

### 4. Delete the approved list

```bash
while IFS=$(printf '\t') read -r kind b sha; do
  [ -n "$b" ] && [ -n "$sha" ] || { echo "skip malformed row: '$b' '$sha'" >&2; continue; }
  [ "$(git rev-parse "$b")" = "$sha" ] || { echo "skip $b: tip moved since approval" >&2; continue; }
  git branch -D "$b"
done < "$CANDIDATES"
git branch --list
```

- `-D` is used for every kind, after the tip SHA check. `git branch -d` checks the merge against `HEAD` or the upstream, not `origin/$BASE`, so it refuses valid candidates unless run from an up-to-date default branch, and it always refuses squash merges
- To restore a deleted branch: `git branch <name> <sha>` with the SHA from the list
- Finish by reporting the deleted branches and the remaining branch list

## Notes

- Never delete automatically. Always show the list and get confirmation first
- Remote branches are not touched. The fetch only prunes remote-tracking refs

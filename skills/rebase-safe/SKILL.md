---
name: rebase-safe
description: "Rebase the current branch onto its base branch, resolving only the conflicting hunks of documentation files in favor of the base, asking the user about every other conflict, then force-pushing with a pinned lease. Use when a PR branch needs to catch up with its base. Requirements: git 2.38 or later, optionally gh. Triggers: rebase, rebase safe, safe rebase, rebase して, 安全に rebase."
---

# Safe Rebase

Rebase onto the base branch. Conflicts in documentation files are resolved in favor of the base side at hunk level, so the branch's non-conflicting doc edits survive. Every other conflict goes to the user.

Run the commands of steps 1 to 5 in one shell, because the variables carry over. Step 1 prints `BR`, `BASE`, `ORIG` and `REMOTE_SHA`. If the shell is restarted mid-rebase, set them again from that output; do not re-fetch `REMOTE_SHA`, or the lease would cover pushes made after the start.

Run everything from the repository top level: the index paths used in step 3 (`:2:<file>`) are relative to it.

The base is assumed to live on `origin`. For a fork PR whose base repository is another remote, fetch that remote and use it in place of `origin/$BASE`.

## Usage

```text
rebase-safe [BASE_BRANCH]
```

- If BASE_BRANCH is omitted, the PR's base branch is detected, falling back to the remote default branch

## Steps

### 1. Pre-flight and base detection

```bash
git status --porcelain
BR=$(git branch --show-current)
BASE=${BASE_BRANCH:-$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null)}
[ -n "$BASE" ] || { BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD) && BASE=${BASE#origin/}; }
git fetch origin || echo "fetch failed" >&2
ORIG=$(git rev-parse HEAD)
echo "merge commits in the rewrite range:"; git rev-list --merges "origin/$BASE..HEAD"
REMOTE_SHA=$(git rev-parse --verify -q "origin/$BR")
[ -z "$REMOTE_SHA" ] || { echo "unpushed:"; git rev-list "origin/$BR..HEAD"; echo "remote-only:"; git rev-list "HEAD..origin/$BR"; }
echo "BR=$BR BASE=$BASE ORIG=$ORIG REMOTE_SHA=$REMOTE_SHA"
```

- Stop and ask the user if `git status --porcelain` prints anything, if the fetch failed, or if `BR` or `BASE` is empty (an empty `BR` means a detached HEAD)
- Stop and ask the user if any merge commit is listed: the rebase would flatten it
- Set `BASE_BRANCH` to the argument, if one was given, before running the block
- Stop if anything is listed under `remote-only:`: someone pushed commits the local branch lacks, and a force push would drop them
- Commits listed under `unpushed:` would be rewritten and pushed too; continue only on explicit confirmation
- If `REMOTE_SHA` is empty, `origin/$BR` does not exist and there is nothing to force-push: use a plain `git push -u origin "HEAD:refs/heads/$BR"` in step 5 instead
- Create the backup ref and keep it until the user confirms the result: `git branch "backup/$BR" "$ORIG"`. If that ref already exists, stop and ask

### 2. Start the rebase

```bash
git rebase --no-rerere-autoupdate --no-update-refs "origin/$BASE"
```

- `--no-rerere-autoupdate` keeps rerere from staging a source conflict on its own, and `--no-update-refs` keeps `rebase.updateRefs` from moving other branches such as `backup/*`
- To give up at any point: `git rebase --abort`. After the rebase finished, `git reset --hard "backup/$BR"` restores the original (ask the user first)

### 3. Conflict resolution loop

When the rebase stops on a conflict, list the conflicted files:

```bash
git diff --name-only --diff-filter=U
```

#### a. Classify each file

- Auto-resolve only documentation: `docs/**/*.md` and `*.md` in the repository root
- Everything else, including files that match no known category (source, Terraform, YAML, lockfiles, `.proto`, SQL, Dockerfiles, anything unfamiliar), goes to the user. Show the conflict and wait for an explicit decision on which side to keep

#### b. Resolve documentation files

During a rebase, "ours" (stage 2) is the base side and "theirs" (stage 3) is the branch commit being replayed. `git checkout --ours -- <file>` would take the whole file from the base and drop the branch's non-conflicting edits in it, so merge hunk by hunk instead:

```bash
resolve_doc() {
  f=$1; t=$(mktemp -d); rc=0
  if git ls-files -u -- "$f" | awk '$1 == 120000 { found = 1 } END { exit !found }'; then
    echo "ask the user: $f is a symlink in at least one stage" >&2; rc=1
  else
    case "$(git ls-files -u -- "$f" | awk '{print $3}' | sort -u | tr -d '\n')" in
      123)
        git show ":2:$f" > "$t/ours" && git show ":1:$f" > "$t/base" && git show ":3:$f" > "$t/theirs" &&
          git merge-file --ours -p "$t/ours" "$t/base" "$t/theirs" > "$t/res" &&
          ! grep -n -e '^<<<<<<< ' -e '^>>>>>>> ' "$t/res" &&
          cat "$t/res" > "$f" && git add -- "$f" || rc=1 ;;
      13) git rm -q -- "$f" || rc=1 ;;
      12) git add -- "$f" || rc=1 ;;
      23) echo "ask the user: $f was added on both sides" >&2; rc=1 ;;
      *) echo "ask the user: $f has unexpected conflict stages" >&2; rc=1 ;;
    esac
  fi
  rm -rf "$t"
  return $rc
}
```

- Run `resolve_doc <file>` for each documentation file from step a. A non-zero return means the file is still conflicted and goes to the user
- Stage `123` (modified on both sides): conflicting hunks take the base, other hunks keep the branch's edits
- Stage `23` (added on both sides) is never auto-resolved: with no common base the whole file is one conflict, so the merge would drop all of the branch's edits
- A symlink in any stage is never auto-resolved: writing the merged text through it would overwrite the link target
- Stage `13`: the base deleted the file, so the deletion is taken
- Stage `12`: the branch deleted a file the base modified, so the base version is kept
- The marker check runs on the merged temp result, before anything is written to the file, so a hit leaves git's conflict state untouched and the function returns non-zero. It looks only for `<<<<<<< ` and `>>>>>>> `: `=======` alone is also a Markdown setext heading underline, and `git diff --check` flags the trailing double space of a Markdown hard line break
- Record every file resolved this way. Its conflicting hunks of the branch's edits are dropped, which the final report must say

#### c. Check that nothing is unresolved

```bash
git diff --name-only --diff-filter=U
```

- Go on to step d only when this prints nothing, meaning every conflicted file is resolved and staged
- Before `git add` of a file the user resolved by hand, run `git grep -n -e '^<<<<<<< ' -e '^>>>>>>> ' -- <file>`; it must print nothing

#### d. Continue

```bash
if [ -z "$(git diff --name-only --diff-filter=U)" ]; then
  if git diff --cached --quiet; then git rebase --skip; else GIT_EDITOR=true git rebase --continue; fi
else
  echo "unresolved files remain: do not continue" >&2
fi
```

- When the resolution leaves the commit empty, `git diff --cached --quiet` succeeds and the commit is skipped with `git rebase --skip`
- Both rebase commands exit non-zero when the next commit conflicts; that is the loop continuing, not a failure
- Repeat step 3 until the rebase finishes

### 4. Check the result

```bash
git log --oneline "origin/$BASE..HEAD"
```

- Confirm the commit list is what the user expects before pushing

### 5. Force push

```bash
git push --force-with-lease="refs/heads/$BR:$REMOTE_SHA" origin "HEAD:refs/heads/$BR" \
  && git fetch origin \
  && [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BR")" ] \
  && echo "pushed: origin/$BR is at $(git rev-parse HEAD)" \
  || echo "STOP: the push failed or origin/$BR differs from HEAD"
```

- The lease is pinned to the SHA recorded in step 1, so the push fails if someone else pushed to the branch in between. Do not retry with plain `--force`; ask the user
- Only the `pushed:` line means success; a `STOP:` line means the push was rejected or did not land

### 6. Report the result

- The list of files resolved automatically, with the warning that the branch's edits in their conflicting hunks were dropped
- The list of files the user decided on (if any)
- The number of commits after the rebase and the backup ref name

## Notes

- Use `git rebase --skip` only for a commit that is already contained in the base or that became empty after resolution

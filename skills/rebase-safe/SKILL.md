---
name: rebase-safe
description: "Rebase the current branch onto its base branch, resolving only the conflicting hunks of documentation files in favor of the base, asking the user about every other conflict, then force-pushing with a pinned lease. Use when a PR branch needs to catch up with its base. Requirements: git, optionally gh. Triggers: rebase, rebase safe, safe rebase, rebase して, 安全に rebase."
---

# Safe Rebase

Rebase onto the base branch. Conflicts in documentation files are resolved in favor of the base side at hunk level, so the branch's non-conflicting doc edits survive. Every other conflict goes to the user.

Run the commands of steps 1 to 5 in one shell, because the variables carry over. If the shell was restarted, re-derive `BR`, `BASE`, `ORIG` and `REMOTE_SHA` first.

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
git fetch origin
ORIG=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse --verify -q "origin/$BR")
[ -z "$REMOTE_SHA" ] || git rev-list "origin/$BR..HEAD"
echo "BR=$BR BASE=$BASE ORIG=$ORIG REMOTE_SHA=$REMOTE_SHA"
```

- Stop and ask the user if `git status --porcelain` prints anything, if `BASE` is empty, or if `git rev-list` lists unpushed commits (they would be rewritten and pushed too; continue only on explicit confirmation)
- Set `BASE_BRANCH` to the argument, if one was given, before running the block
- If `REMOTE_SHA` is empty, `origin/$BR` does not exist and there is nothing to force-push: use a plain `git push -u origin HEAD` in step 5 instead
- Create the backup ref and keep it until the user confirms the result: `git branch "backup/$BR" "$ORIG"`. If that ref already exists, stop and ask

### 2. Start the rebase

```bash
git rebase "origin/$BASE"
```

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
  f=$1; t=$(mktemp -d)
  case "$(git ls-files -u -- "$f" | awk '{print $3}' | sort -u | tr -d '\n')" in
    123|23)
      git show ":2:$f" > "$t/ours" && { git show ":1:$f" > "$t/base" 2>/dev/null || : > "$t/base"; } && git show ":3:$f" > "$t/theirs" &&
        git merge-file --ours -p "$t/ours" "$t/base" "$t/theirs" > "$t/res" && cat "$t/res" > "$f" &&
        git diff --check -- "$f" && git add -- "$f" ;;
    13) git rm -q -- "$f" ;;
    12) git add -- "$f" ;;
    *) echo "ask the user: $f has unexpected conflict stages" >&2; return 1 ;;
  esac
  rm -rf "$t"
}
```

- Run `resolve_doc <file>` for each documentation file from step a
- Stages `123` and `23` (modified on both sides, or added on both sides): conflicting hunks take the base, other hunks keep the branch's edits
- Stage `13`: the base deleted the file, so the deletion is taken
- Stage `12`: the branch deleted a file the base modified, so the base version is kept
- `git diff --check` must pass before `git add`, otherwise the function stops and a conflict marker is still in the file
- Record every file resolved this way. Its conflicting hunks of the branch's edits are dropped, which the final report must say

#### c. Continue

```bash
git diff --name-only --diff-filter=U
if git diff --cached --quiet; then git rebase --skip; else GIT_EDITOR=true git rebase --continue; fi
```

- Run this only when the first command prints nothing, meaning every conflicted file is resolved and staged
- When the resolution leaves the commit empty, `git diff --cached --quiet` succeeds and the commit is skipped with `git rebase --skip`
- Both commands exit non-zero when the next commit conflicts; that is the loop continuing, not a failure
- Before `git add` of a file the user resolved by hand, run `git diff --check -- <file>` and fix any leftover conflict marker
- Repeat step 3 until the rebase finishes

### 4. Check the result

```bash
git log --oneline "origin/$BASE..HEAD"
```

- Confirm the commit list is what the user expects before pushing

### 5. Force push

```bash
git push --force-with-lease="$BR:$REMOTE_SHA" origin HEAD
git fetch origin
git rev-parse HEAD "origin/$BR"
```

- The lease is pinned to the SHA recorded in step 1, so the push fails if someone else pushed to the branch in between. Do not retry with plain `--force`; ask the user
- The two SHAs from the last command must be equal; if they differ the push was rejected

### 6. Report the result

- The list of files resolved automatically, with the warning that the branch's edits in their conflicting hunks were dropped
- The list of files the user decided on (if any)
- The number of commits after the rebase and the backup ref name

## Notes

- Use `git rebase --skip` only for a commit that is already contained in the base or that became empty after resolution

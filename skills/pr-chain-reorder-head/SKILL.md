---
name: pr-chain-reorder-head
description: "Insert a new branch X below the root of a PR chain and reconnect every rung with `rebase --onto` from recorded SHAs and a pinned `--force-with-lease`, with backups, conflict handling and rollback. Use when BASE -> A -> B -> C needs to become BASE -> X -> A -> B -> C. Triggers: PR チェーン先頭挿入, PR チェーン組み替え."
---

# pr-chain-reorder-head

Insert another branch X below the root of a PR chain (BASE -> A -> B -> C -> ...) and reorganize it into `BASE -> X -> A -> B -> C -> ...`.

Terms: a rung is one PR of the chain; the root is the rung directly on BASE (A); the leaf is the top rung; BASE is the branch the root PR currently targets.

Requirements: `git` 2.38 or later (for `--no-update-refs`), `gh` (authenticated). If the PRs were created with a stacking tool such as `gh stack`, use that tool's own commands to change bases instead of `gh pr edit --base`.

Typical use case:

- A feature branch X that has been running in parallel off BASE (for example a new feature) should get an existing refactoring chain on top of it, so X can be run on its own with the improvements applied
- X is often only a test target (a temporary rearrangement for verification, not a permanent structural change)

## Prerequisites

- X has already been pushed, branched from BASE, and has its own PR targeting BASE (step 0 checks this)
- The base of the root A is BASE
- The base of each following PR is the previous rung (the standard chain form)
- The working tree is clean and all branches are in sync between local and origin (step 0 checks this)

## Procedure

Run each step in one shell session. The recorded SHAs live in the `backup/<branch>` refs (original tips) and the `refs/pushed/<branch>` refs (what step 1 pushed or was about to push), so no variable has to survive between steps.

### 0. Check and record

```bash
BASE=<base branch name, e.g. main>   # `gh pr view <PR number of A> --json baseRefName --jq .baseRefName`
git fetch origin || echo "STOP: fetch failed"

# Any output from these checks is a stop condition: fix it or ask the user before going on
git status --porcelain
for b in <X> <A> <B> <C> ...; do
  [ "$(git rev-parse "refs/heads/${b}")" = "$(git rev-parse "origin/${b}")" ] || echo "DIFF ${b}"
done
[ "$(gh pr view <PR number of X> --json baseRefName --jq .baseRefName)" = "$BASE" ] || echo "X has no PR targeting $BASE"
git merge-base --is-ancestor "origin/$BASE" "origin/<X>" || echo "X is behind origin/$BASE"
# Merge commits in a rung's own range would be flattened by its rebase
prev="origin/$BASE"
for b in <A> <B> <C> ...; do
  m=$(git rev-list --merges "$prev..origin/${b}") || echo "STOP: rev-list failed for ${b}"
  [ -z "$m" ] || echo "MERGE COMMITS in ${b}"
  prev="origin/${b}"
done

# Record every branch's original tip (these refs are also the rollback source)
for b in <X> <A> <B> <C> ...; do
  # An existing backup is an earlier rollback point: stop and ask the user instead of overwriting it
  git branch --no-track "backup/${b}" "origin/${b}" || echo "STOP: backup/${b} exists or cannot be created"
  echo "${b} $(git rev-parse "backup/${b}")"
done
```

If X is behind BASE, either bring X up to date first (rebase X onto `origin/$BASE` and push it with a lease; ask X's owner if it is not yours), then run step 0 again, or accept it: step 2 then prints `NOT STACKED X on origin/$BASE`, which is expected.

### 1. Rebuild the chain, root first

For each rung R in order A, B, C, ..., with P the rung below it in the new chain (X for A, then A for B, and so on) and OLD_PARENT the old parent's original tip: `origin/$BASE` for A, and `backup/<P>` for every later rung. Use `--onto` with the old parent's tip for every rung: it replays only R's own commits, so commits that were rewritten in the rung below are not applied a second time.

```bash
# rung A: P = X, old parent = origin/$BASE
# One chain per rung: a stopped rebase must not retarget the PR or push. --no-update-refs keeps rebase.updateRefs from moving backup/* or other rungs
# The retarget comes before the push so the PR never shows X's commits as its own
# refs/pushed/<A> is recorded before the push (the rollback lease) and kept if the push fails: Rolling back decides from the remote's actual tip
git switch <A> \
  && git rebase --no-update-refs --onto <X> "origin/$BASE" <A> \
  && gh pr edit <PR number of A> --base <X> \
  && git update-ref refs/pushed/<A> "$(git rev-parse <A>)" \
  && git push --force-with-lease="refs/heads/<A>:$(git rev-parse backup/<A>)" origin <A>

# rung B: P = A, old parent = backup/A
git switch <B> \
  && git rebase --no-update-refs --onto <A> "$(git rev-parse backup/<A>)" <B> \
  && gh pr edit <PR number of B> --base <A> \
  && git update-ref refs/pushed/<B> "$(git rev-parse <B>)" \
  && git push --force-with-lease="refs/heads/<B>:$(git rev-parse backup/<B>)" origin <B>
# gh pr edit changes nothing when B already targets A; it stays in the chain for uniformity

# rung C and the rest: same shape, P = B, old parent = backup/B, and so on
```

The lease is pinned to the SHA recorded in step 0, so the push is refused if the remote branch moved since then.

### 2. Check the result

```bash
git fetch origin || echo "STOP: fetch failed, the checks below would read stale refs"
prev="origin/$BASE"
for b in <X> <A> <B> <C> ...; do
  if git merge-base --is-ancestor "$prev" "origin/${b}"; then echo "ok ${b} on ${prev}"; else echo "NOT STACKED ${b} on ${prev}"; fi
  prev="origin/${b}"
done
# Each PR's base must be the rung below it: X -> BASE, A -> X, B -> A, C -> B. Any WRONG PR BASE line is a failure
prev="$BASE"
while read -r b pr; do
  [ "$(gh pr view "$pr" --json baseRefName --jq .baseRefName)" = "$prev" ] || echo "WRONG PR BASE: #${pr} (${b}) should target ${prev}"
  prev="$b"
done <<'EOF'
<X> <PR number of X>
<A> <PR number of A>
<B> <PR number of B>
<C> <PR number of C>
EOF
```

Then run workflow_dispatch (or the relevant check) on the leaf to confirm it works. If a small fix is needed, push a fixup commit to the leaf.

## Handling conflicts

- A `git rebase` stops with a conflict: resolve it, run `git diff --check` (it must print nothing), then `git add <file>` and `git rebase --continue`. To give up on this rung, run `git rebase --abort`; that restores only the rung being rebased. Rungs already pushed stay rewritten and retargeted, and the rungs above them still carry the old history, so go to Rolling back or finish the cascade.
- After `git rebase --continue` finishes the rebase, the rung is not done: the chain in step 1 stopped before its retarget, record and push. Run them now (shown for rung A; use the rung's own `<P>`, `<PR number>` and `backup/<R>`):

  ```bash
  gh pr edit <PR number of A> --base <X> \
    && git update-ref refs/pushed/<A> "$(git rev-parse <A>)" \
    && git push --force-with-lease="refs/heads/<A>:$(git rev-parse backup/<A>)" origin <A>
  ```

- A commit that is already present in the new parent (the same change duplicated across rungs): `git rebase --skip` is fine. `git rebase` detects duplicates by patch-id, but a commit whose content changed (rewritten by a conflict resolution) is not recognized as a duplicate. The sign that skip is OK is that an equivalent-content commit with a new SHA already exists in the rungs below.
- modify/delete conflict: if the intent of the deleting commit is clear, `git rm <file>`; if the file should stay, `git add <file>`; then `git rebase --continue`.
- Many unrelated commits are being re-applied on a rung: the old parent SHA is wrong. Abort, and check that `git rev-parse backup/<P>` is the tip the rung was originally based on.

## Rolling back

Put every branch, remote and local, back at its recorded tip and the root PR back on its original base. Each push is leased to the SHA step 1 pushed (`refs/pushed/<branch>`), not to `origin/<branch>`, so a push by someone else after step 1 is refused instead of overwritten. A rung without a `refs/pushed` ref was never pushed by this procedure, but its remote must still equal `backup/<b>`; if someone else moved it, stop. A push can fail or be interrupted after the ref was recorded, so the ref is never deleted for that reason; the remote's actual tip decides (`git ls-remote origin refs/heads/<b>`): equal to `backup/<b>` means nothing was pushed (restore only the local branch), equal to `refs/pushed/<b>` means it was pushed (lease push, then restore), anything else means someone else moved it, so stop.

```bash
# Any output from the next line is a stop condition (the reset below would discard it)
git status --porcelain
cur=$(git branch --show-current)
failed=
for b in <A> <B> <C> ...; do
  ok=
  p=$(git rev-parse -q --verify "refs/pushed/${b}") || p=
  remote=$(git ls-remote origin "refs/heads/${b}" | cut -f1)
  if [ "$remote" = "$(git rev-parse "backup/${b}")" ]; then ok=1
  elif [ -n "$p" ] && [ "$remote" = "$p" ]; then git push --force-with-lease="refs/heads/${b}:${p}" origin "backup/${b}:refs/heads/${b}" && ok=1
  fi
  [ -n "$ok" ] \
    && if [ "$b" = "$cur" ]; then git reset --hard "backup/${b}"; else git branch -f "$b" "backup/${b}"; fi \
    || { echo "STOP: could not restore ${b}"; failed=1; break; }
done
# Revert the PR base only when every branch was restored
[ -z "$failed" ] && gh pr edit <PR number of A> --base "$BASE"
# B, C, ... targeted the previous rung before and still do: no retarget needed
```

Delete the `backup/*` and `refs/pushed/*` refs (`git update-ref -d <ref>`) only after the new chain or the rollback is confirmed.

## Chains where each rung has a different owner

When rebuilding a chain in which several people or agents each own one PR, do not rebase and push every rung yourself. If an owner has unpushed commits locally, your push can succeed under the lease and still collide with theirs on their next push.

- Rebase only the rungs you own. For rungs that have an owner, ask them to "set your base to `<the rung below>` and `rebase --onto` it from the old tip of that rung" (a PR comment works)
- Proceed one rung at a time from the bottom, and ask for the upper rungs only after the tip of the lower rung is settled (track it with a status table that shows, for each rung, how many commits it is behind the tip of the rung directly below)
- Take over only rungs whose owner is absent or not responding, and leave a PR comment saying you took them over

## Related

- pr-chain-verify: add per-PR verification commits to the same kind of chain
- rebase-safe: an ordinary rebase to follow the base

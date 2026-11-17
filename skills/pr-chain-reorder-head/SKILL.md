---
name: pr-chain-reorder-head
description: "Insert a new branch at the head of a PR chain and reconnect the whole chain with rebase --onto and --force-with-lease, including conflict handling, cleanup and how to roll back. Use when main -> A -> B -> C needs to become main -> X -> A -> B -> C. Triggers: insert at head of PR chain, reorder PR chain, PR チェーン先頭挿入, PR チェーン組み替え."
---

# pr-chain-reorder-head

How to insert another branch X at the head of a PR chain (main -> A -> B -> C -> ...) and reorganize it into `main -> X -> A -> B -> C -> ...`.

It cannot be used on stacked PRs (created with `gh stack`): `gh pr edit --base` is rejected for them, so reorder those with `gh stack modify` instead.

Typical use case:

- A feature branch X that has been running in parallel off main (for example a new feature) should get an existing refactoring / cache-improvement chain on top of it, so X can be run on its own with the improvements applied
- X is often only a test target (a temporary rearrangement for verification, not a permanent structural change)

## Prerequisites

- X (the new head) has already been pushed, branched from main
- The base of the current chain head A is main
- The base of each following PR is the head of the previous PR (the standard chain form)
- All branches are in sync between local and origin (confirm with rev-parse)

## Procedure

```bash
# 0. fetch + check that local and origin match
git fetch origin <X> <A> <B> <C> ...
for b in <X> <A> <B> <C> ...; do
  [ "$(git rev-parse $b)" = "$(git rev-parse origin/$b)" ] || echo "DIFF $b"
done

# 1. Rebase A from main onto X with rebase --onto (upstream is the original base, i.e. origin/main)
git switch <A>
git rebase --onto <X> origin/main
git push --force-with-lease origin <A>
gh pr edit <PR number of A> --base <X>   # change the PR base from main to X

# 2. Rebase each following branch onto the previous one, in order
git switch <B> && git rebase <A> && git push --force-with-lease origin <B>
git switch <C> && git rebase <B> && git push --force-with-lease origin <C>
# ...and so on
```

## Handling conflicts

- Same commit duplicated across several chains (typical during a rebase cascade): `git rebase --skip` is fine. `git rebase` detects duplicates by patch-id, but a commit whose content changed (rewritten by a conflict resolution) is not recognized as a duplicate. The sign that skip is OK is that an equivalent-content commit with a new SHA already exists in the preceding chain.
- Deciding whether to skip a WIP commit that conflicts: if the new head X makes a WIP commit (an install / scaffold commit) conflict on something like `pnpm-lock.yaml`, and you plan to rewrite that WIP commit on the new base anyway, dropping it with `git rebase --skip` is fine. Re-add or regenerate any untracked leftovers on disk (for example a submodule clone) by hand. For example, when a new head that bumps the Node.js version was inserted below a branch whose first commit was `chore(WIP): install <tool> <old-version>`, skip that commit and reinstall the tool on the new base at its current version.
- add/delete conflict (`modify/delete`): if the intent of the deleting commit is clear, `git rm <file>`; if the file should stay, leave it as is, then `git add` and `git rebase --continue`.
- A wide set of commits being re-applied on the tip branch (abnormal): narrow the range with `git rebase --onto <new-base> <old-head-of-prev-branch> <tip>` so that only the tip's own commits are applied.

## Cleanup

- Run workflow_dispatch (or the relevant check) on the tip to confirm it works. If a small runbook fix is needed, push a fixup commit to the tip.
- To undo: re-point each PR back to its original base and reset to the original SHAs (recover them from the reflog).

## Related

- For an ordinary rebase to follow the base, use the rebase-safe skill

## Chains where each rung has a different owner

When rebuilding a chain in which several people or agents each own one PR, do not rebase and push every rung yourself. If an owner has unpushed commits locally, your push can succeed under the lease and still collide with theirs on their next push.

- Rebase only the rungs you own. For rungs that have an owner, ask them to "set your base to `<the rung below>` and `rebase --onto`" (a PR comment works)
- Proceed one rung at a time from the bottom, and ask for the upper rungs only after the head of the lower rung is settled (track it with a status table that shows, for each rung, how many commits it is behind the head of the rung directly below; define the term where it first appears)
- Take over only rungs whose owner is absent or not responding, and leave a PR comment saying you took them over

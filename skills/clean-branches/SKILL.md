---
name: clean-branches
description: "Clean up local git branches: prune remote-tracking refs that were deleted on the remote, detect local branches already merged (regular merge via --merged, squash merge via git cherry), and delete them after the user confirms. Triggers: clean branches, delete merged branches, prune local branches, ブランチ掃除."
---

# Git Clean Branches

Tidy up the local branches of the current repo. Regular merges are detected with `--merged`, and squash merges with `git cherry -v`.

## Steps

1. Remove tracking refs that were deleted on the remote with `git fetch --prune`
2. List the local branches that were merged normally:
   ```bash
   git branch --merged main | grep -v '^\* \|^  main$'
   ```
3. Detect squash-merged branches with `git cherry -v`:
   ```bash
   # Run the cherry check for every local branch except main
   for b in $(git branch --format='%(refname:short)' | grep -v '^main$'); do
     # If the cherry output has no "+ <sha>" line, every commit is already in main
     if ! git cherry -v main "$b" | grep -q '^+'; then
       echo "squash-merged: $b"
     fi
   done
   ```
   - `-` line = already in main by content (including squash merges)
   - `+` line = not yet in main
4. Show the user the list of deletion candidates (regular merges + squash merges) and get confirmation
5. After approval, delete:
   ```bash
   # Regular merges are deleted safely with -d
   git branch --merged main | grep -v '^\* \|^  main$' | xargs -r git branch -d
   # Squash merges would be "not fully merged" with -d, so use -D
   git branch -D <squash-merged-branch>
   ```
6. Show the list of remaining branches and report completion

## Notes

- If the default branch is not `main`, read it accordingly
- Squash merge detection uses `git cherry -v base branch`. A `-` line means already included by content, a `+` line means not yet included. Even if the SHAs differ, content equivalence is judged by patch-id
- Deleting a squash-merged branch requires `-D` (force). `-d` refuses with "not fully merged"
- Always show the list and get confirmation before deleting. Never delete automatically
- Exclude the current branch (HEAD) from the deletion candidates

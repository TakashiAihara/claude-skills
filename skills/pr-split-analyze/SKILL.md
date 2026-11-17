---
name: pr-split-analyze
description: "Investigate a large pull request and propose how to split it into smaller, reviewable PRs: measure the diff, classify changed files by layer, domain and dependency, and output a one-way chain of PRs with sizes and bases. Use when a PR diff is too big to review. Execute the plan with the pr-split-execute skill. Triggers: PR split, pr split analyze, large diff, PR 分割, 差分大きい."
---

# PR Split Analyze

Investigate how a PR with a large diff should be split, and propose a split plan.

## Workflow

### 1. Check the diff size

```bash
# Diff size against the base branch
git diff --stat <base-branch>...HEAD
git diff --numstat <base-branch>...HEAD | awk '{add+=$1; del+=$2} END {print "+" add " -" del " = " add+del " lines"}'
```

### 2. Analyze the commit history

```bash
# List the commits on the branch (look for groups with one responsibility each)
git log --oneline <base-branch>..HEAD
```

### 3. Classify the changed files

Classify the changed files along these axes:

- By layer: infrastructure / migration / application / docs / test
- By domain: feature area (for example auth / webhooks / reporting)
- By dependency: which changes are prerequisites for other changes

### 4. Propose a split

Propose it in this format:

```text
## Split plan

### PR 1: <title> (about XXX lines)
- Scope: <list of files or commit range>
- Depends on: none (merge first)
- Base: <base-branch>

### PR 2: <title> (about XXX lines)
- Scope: <list of files or commit range>
- Depends on: PR 1
- Base: PR 1's branch

### PR 3: ...
```

### 5. Principles for splitting

- Each PR can be reviewed on its own
- Dependencies run in one direction (PR 1 -> PR 2 -> PR 3)
- Aim for 500 to 1000 lines per PR (2000 at most)
- The natural order is infrastructure -> migration -> application -> test
- If the split is hard, explain why

## Notes

- Once the split plan is decided, run it with the pr-split-execute skill
- Get the user's approval before executing the split

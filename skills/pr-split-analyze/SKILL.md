---
name: pr-split-analyze
description: "Investigate a large pull request and propose how to split it into a one-way chain of smaller, reviewable PRs, with sizes and bases. Use when a PR diff is too big to review or the user asks to split a PR; execute the approved plan with the pr-split-execute skill. Triggers: PR 分割, 差分大きい, PR が大きすぎる."
---

# PR Split Analyze

Investigate how a PR with a large diff should be split, and propose a split plan.

Requirements: `git`; `gh` is optional (it only provides the PR's base branch, and the snippet falls back without it).

## Workflow

### 1. Check the diff size

Run the commands of this step in one shell, because `BASE_BRANCH` is reused.

```bash
# Base: the PR's base if there is a PR, otherwise the remote default branch
BASE_BRANCH=$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null) || BASE_BRANCH=
[ -n "$BASE_BRANCH" ] || BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
git fetch origin "$BASE_BRANCH"

# Lockfiles and generated files are not review effort: leave them out of the size (extend the excludes for the repository)
EXCLUDES=(':(exclude)*.lock' ':(exclude)package-lock.json' ':(exclude)pnpm-lock.yaml' ':(exclude)go.sum' ':(exclude)*.min.js' ':(exclude)*.pb.go')
git diff --stat "origin/$BASE_BRANCH...HEAD" -- . "${EXCLUDES[@]}"
git diff --numstat "origin/$BASE_BRANCH...HEAD" -- . "${EXCLUDES[@]}" | awk '{add+=$1; del+=$2} END {print "+" add " -" del " = " add+del " lines"}'
```

### 2. Analyze the commit history

```bash
# List the commits on the branch (look for groups with one responsibility each)
git log --oneline "origin/$BASE_BRANCH..HEAD"
```

### 3. Classify the changed files

Classify the changed files along these axes:

- By layer: infrastructure / migration / application / docs / test
- By domain: feature area (for example one module or package per PR)
- By dependency: which changes are prerequisites for other changes

### 4. Principles for splitting

- Each PR builds and passes its own tests, so it can be reviewed and merged on its own
- Keep tests with the code they cover; do not defer them to a final "tests" PR
- Dependencies run in one direction (PR 1 -> PR 2 -> PR 3)
- Default size: 500 to 1000 changed lines per PR (2000 at most), counted without lockfiles and generated files; the repository's CONTRIBUTING guidance wins when it states other numbers
- The natural order is infrastructure -> migration -> application (with its tests); docs go with the change they describe
- If the split is hard, explain why

### 5. Propose a split

Propose it in this format:

```text
## Split plan

### PR 1: <title> (about XXX lines)
- Scope: <list of files or commit range>
- Depends on: none (merge first)
- Base: <base branch>

### PR 2: <title> (about XXX lines)
- Scope: <list of files or commit range>
- Depends on: PR 1
- Base: PR 1's branch

### PR 3: ...
```

## Notes

- Once the split plan is decided, run it with the pr-split-execute skill
- Get the user's approval before executing the split

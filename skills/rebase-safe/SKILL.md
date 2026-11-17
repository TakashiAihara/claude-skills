---
name: rebase-safe
description: "Rebase the current branch onto its base branch, automatically resolving documentation conflicts in favor of the base side, asking the user about source, infrastructure, config and dependency conflicts, then force-pushing with lease. Use when a PR branch needs to catch up with its base. Triggers: rebase, rebase safe, safe rebase, rebase して, 安全に rebase."
---

# Safe Rebase

Rebase onto the base branch. Conflicts in documentation-type files are automatically resolved by taking the base side.

## Usage

```text
rebase-safe [BASE_BRANCH]
```

- If BASE_BRANCH is omitted, the PR's base branch is detected automatically

## Steps

### 1. Identify the base branch

```bash
gh pr view --json baseRefName --jq '.baseRefName'
```

### 2. Fetch and start the rebase

```bash
git fetch origin <BASE_BRANCH>
git rebase origin/<BASE_BRANCH>
```

### 3. Conflict resolution loop

When a conflict occurs:

#### a. Get the conflicted files

```bash
git diff --name-only --diff-filter=U
```

#### b. Classify the files and resolve them

Automatic resolution (take the base side):

- `docs/**/*.md` - documentation files
- `*.md` - Markdown files in the root

```bash
git checkout origin/<BASE_BRANCH> -- <file>
git add <file>
```

Manual confirmation required:

- `*.ts`, `*.tsx`, `*.js` - source code
- `*.tf` - Terraform
- `*.yaml`, `*.yml` - configuration files
- `package.json`, `pnpm-lock.yaml` - dependencies

If there are files that need manual confirmation, show their contents to the user and ask for a decision.

#### c. Continue

```bash
git rebase --continue
```

Repeat until there are no more conflicts.

### 4. Force push

```bash
git push --force-with-lease
```

### 5. Report the result

- The list of files that were resolved automatically
- The list of files that needed manual confirmation (if any)
- The number of commits after the rebase

## Notes

- Use `git rebase --skip` only for a conflict on a commit that is already contained in the base
- Ask the user about conflicts in infrastructure files (wait for an instruction such as "the same as origin/main is correct")
- Check the commit list with `git log --oneline` before the force push

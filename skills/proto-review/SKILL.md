---
name: proto-review
description: "Review protobuf files for design quality and compliance with Google's API Improvement Proposals (AIP): naming, Request/Response messages, enum UNSPECIFIED values, reserved fields, consistency with design docs, and extensibility, plus buf lint/format/breaking checks, with each finding scoped to the PR diff or marked pre-existing. Use when reviewing a PR or branch that changes .proto files. Triggers: proto review, review proto files, protobuf review, proto レビュー."
---

# Proto Review

Review the design of proto files changed on the current branch.

Requirements: `git`; `gh` (optional, to find the PR base); `buf` (optional, for the mechanical checks in step 3).

## Review procedure

### 1. Decide the base branch and list the changed proto files

In a middle PR of a PR chain the base is not the default branch, so diffing against the default branch mixes in other PRs' changes and breaks the scope judgment. Run the commands of steps 1-3 in one shell, because `BASE` is reused.

```bash
git fetch origin || { echo "fetch failed"; exit 1; }
BASE=$(gh pr view --json baseRefName --jq .baseRefName 2>/dev/null)
BASE=${BASE:-$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')}
echo "diff base = origin/$BASE"

# Three-dot: only what this branch changed since it forked from the base.
# Status A = new file, M = modified, D = deleted, R<score> = renamed (old path, new path).
git diff -M --name-status "origin/$BASE...HEAD" -- '*.proto'
```

- If the fetch fails or `BASE` is empty, stop and ask the user for the base branch.
- Use the three-dot form everywhere. `git diff "origin/$BASE"` compares the working tree with the base tip, so uncommitted edits and changes made only on the base show up as if the PR made them.
- The three-dot diff sees commits only: commit or stash local edits first, or the review silently skips them.
- Keep rename detection on (`-M`). Only status `A` is a new file; with `--no-renames` a renamed file shows as deleted plus added, so the whole file would look new.
- If no proto files changed, ask the user.

### 2. Gather context

Read the following in parallel:

- The whole of each changed proto file (the whole file, not just the diff)
- Related design documents (for example under `docs/design-docs/`), if any
- The diff: `git diff "origin/$BASE...HEAD" -- <proto files>`

#### Scope principle: focus inside the PR diff, file the rest as separate issues

Read the whole file as context, but limit findings to what the PR changed. Problems that already existed on the base are not this PR's responsibility, and mixing them in costs confirmation round trips.

- Problem inside the diff: propose a fix in this PR
- Problem outside the diff: prompt the user to file a separate issue

How to judge each finding:

- A file with status `A` is entirely inside the diff. `git show origin/$BASE:<file>` also fails for it, so do not use that to read old content.
- For a file that existed at the fork point (status `M` or `R`), the added lines are the PR's. Count only added lines, not removed lines or the `---`/`+++` headers. For a renamed file pass both the old and the new path, or the whole file shows as added:

```bash
git diff -M "origin/$BASE...HEAD" -U0 -- <old path> <new path> | grep -E '^\+([^+]|$)'
```

- A finding about something present (a bad field name, a wrong type) is inside the diff only if its line is in the added lines.
- A removed line (`-`) is not automatically a fix. Removing a field, enum value or rpc without a matching `reserved` is a breaking change made by this PR: inside the diff, high severity. Check the removed lines for it.
- A finding about something missing (no `_UNSPECIFIED` value, no `reserved`, no `Response` suffix) cannot be grepped for. Read the diff and judge whether the enclosing enum, message or rpc was added or changed by the PR: if it was, the finding is inside the diff; if the PR did not touch it, it is pre-existing.
- Old content, when needed: `git show "$(git merge-base "origin/$BASE" HEAD):<proto file>"`.

### 3. Mechanical checks with buf (before the manual checklist)

Visual review cannot catch wire compatibility breaks. In a repo with `buf.yaml`, run these from the module root (the directory that holds `buf.yaml`) and include the results in the report.

```bash
# Naming and style
buf lint

# Format drift (--exit-code makes it CI-equivalent)
buf format --diff --exit-code

# Wire breaking check against the base from step 1
buf breaking --against ".git#branch=origin/$BASE"
```

- 0 breaking findings against the base means this PR alone is wire safe.
- For a chain PR, also run `buf breaking --against ".git#branch=origin/<default branch>"` to see the effect of the whole chain stacked on the default branch. A violation that appears only there is not automatically another PR's: check whether this PR's added lines are involved (for example it reuses a number or name that an earlier PR in the chain freed) before attributing it elsewhere, and report the rest separately from this PR's own.
- Missing `reserved`, deleted enum values and changed field types are detected mechanically by `buf breaking`. Cross-check them against the "Need for reserved" item below.

### 4. Review checklist

Report only the items with problems.

#### AIP compliance (https://google.aip.dev/)

| Aspect | What to check |
|------|------------|
| Naming (AIP-140) | Field names are lower_snake_case, message names are PascalCase |
| Request/Response messages | The input and output messages of an RPC follow the `<Method>Request` / `<Method>Response` convention (buf lint rules `RPC_REQUEST_STANDARD_NAME` and `RPC_RESPONSE_STANDARD_NAME`) |
| enum UNSPECIFIED (AIP-126) | The 0th value of an enum is `<ENUM_NAME>_UNSPECIFIED` |
| enum prefix (AIP-126) | Enum values are prefixed with the UPPER_SNAKE_CASE of the enum name (for example `STATUS_ACTIVE`) |
| repeated naming (AIP-140) | repeated fields are plural |
| Use of optional | `optional` is applied only to fields that are really omittable |
| Backwards compatibility (AIP-180) | Existing fields and values keep their numbers, names and types |

#### Consistency

| Aspect | What to check |
|------|------------|
| Consistency with existing messages | The structure matches similar RPCs/messages in the same file (for example how `oneof` is used, field order) |
| Field numbers | Numbers are unique within a message and do not reuse a `reserved` or previously shipped number. Gaps are fine when the numbers are `reserved` or were deliberately skipped |
| Need for reserved | When a field is deleted, only numbers that shipped in a release of the base are turned into `reserved N;`. A number that was added and removed while unmerged has no consumers, so it needs no `reserved`. In the comment on `reserved`, leave one line on how the number was used |
| Message reuse | Existing messages are reused where appropriate (no unnecessary duplicate definitions) |
| Accuracy of comments | The enum value names and field names in comments match the actual definitions |

#### Consistency with the design document

| Aspect | What to check |
|------|------------|
| Field match | Fields in the design document exist in the proto (and vice versa) |
| Required/optional match | Required/optional in the design document matches `optional` in the proto |
| Type match | The design document's description does not contradict the proto field type |
| Naming match | Names in the design document (enum values, etc.) match the actual names in the proto |

#### Extensibility

| Aspect | What to check |
|------|------------|
| Use of oneof | `oneof` is used where variants will be added in the future |
| Avoiding breaking changes | Future extension does not break existing clients |

### 5. Report the results

Severity levels:

- high: breaks wire or source compatibility for existing clients, or contradicts the design document in a way that changes behavior
- medium: violates an AIP rule or the file's own conventions, and will cost a migration to fix later
- low: naming, comment or style issues with no compatibility effect

For each finding, state whether it applies inside the PR diff or is pre-existing on the base.

````markdown
## Proto Review result

Checked: buf lint / format / breaking, AIP compliance, consistency, design document, extensibility.

### Problems

#### 1. [Title of the problem] (severity: high/medium/low, applies to: inside the PR diff / pre-existing on the base)

[Explanation]

```protobuf
// Current
[current code]

// Proposal
[proposed fix]
```

### Summary by scope

- Inside this PR's diff (fix recommended): 1, 2, 4
- Pre-existing on the base (outside the diff, candidates for a separate issue): 3, 5
````

If there are no problems, write one line saying that none were found and which checks ran.

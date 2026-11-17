---
name: proto-review
description: "Review protobuf files for design quality and compliance with Google's API Improvement Proposals (AIP): naming, Request/Response suffixes, enum UNSPECIFIED values, reserved fields, consistency with design docs, extensibility, and buf lint/format/breaking checks, with findings scoped to the PR diff versus pre-existing issues. Triggers: proto review, review proto files, protobuf review, proto レビュー."
---

# Proto Review

Review the design of proto files.

---

## Review procedure

### 1. Identify the target files and decide the base branch

First decide which base branch to diff against. In a middle PR of a PR chain the base is not `main`, so diffing against `main` mixes in the diff of downstream PRs (such as a revert PR) and breaks the scope judgment.

```bash
# Get the base of the PR tied to the branch under review (chain PR aware)
BRANCH=$(git branch --show-current)
BASE=$(gh pr view "$BRANCH" --json baseRefName --jq .baseRefName 2>/dev/null)
BASE=${BASE:-main}   # main if there is no PR
echo "diff base = origin/$BASE"

# Get the proto files changed against that base
git diff "origin/$BASE" --name-only -- '*.proto'
```

Read every `git diff main` / `git show main:` in the following steps as `origin/$BASE` above. Fixing on `main` is fine only for a standalone PR whose base is main.

If no proto files changed, ask the user.

### 2. Gather context

Read the following in parallel:

- The whole of each changed proto file (read the whole file, not just the diff)
- Related design documents (under `docs/design-docs/`), if any
- Check the diff with `git diff main -- <proto files>`

#### Scope principle: focus inside the PR diff, file the rest as separate issues

Read the whole file as context, but by default limit the findings to the areas the PR diff touched. Existing problems on main (outside the diff) are not this PR's responsibility, and mixing them in causes confirmation round trips in proportion to how many out-of-diff items the first report contains:

- Problems inside the diff -> propose fixes in this PR
- Problems outside the diff -> prompt the user to file a separate issue (do not bloat this PR)

How to judge (always run this for each finding):

```bash
DIFF_FILE=$(mktemp)
git diff main -- <proto file> > "$DIFF_FILE"
# Pre-existing on main (still in the whole file at HEAD, but unchanged inside the diff), for example:
git show main:<proto file> | grep -nE '<pattern of the finding>'   # present on main = candidate for outside the diff
grep -E '^[+-]' "$DIFF_FILE" | grep -i '<pattern of the finding>'   # appears in the diff = inside the diff
```

If the user asks back "did you limit this to the changed lines only?", the first report was lacking.

### 3. Review checklist

Review along the checklist below. Do not report items with no problem. Report only the ones with problems.

#### AIP compliance (https://google.aip.dev/)

| Aspect | What to check |
|------|------------|
| Naming | Field names are snake_case, message names are PascalCase |
| Request/Response suffix | The input and output messages of an RPC have the `Request`/`Response` suffix |
| enum UNSPECIFIED | The 0th value of an enum is defined as `_UNSPECIFIED` |
| enum prefix | Enum values are prefixed with the SNAKE_CASE of the enum name (for example `STATUS_ACTIVE`) |
| Use of optional | `optional` is applied only to fields that are really omittable |
| repeated naming | repeated fields are plural |

#### Consistency

| Aspect | What to check |
|------|------------|
| Consistency with existing messages | The structure matches similar RPCs/messages in the same file (for example how `oneof` is used, field order) |
| Field numbers | They are sequential with no gaps and do not collide with reserved numbers |
| Need for reserved | Only field numbers that have shipped in a release of main are turned into `reserved N;` when a field is deleted. A number that was added and then removed while unmerged has zero consumers, so it needs no reserved (no wire accident can happen). In the comment on `reserved`, leave one line on how that number was used in the past |
| Message reuse | Existing messages are reused appropriately (no unnecessary duplicate definitions) |
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
| Use of oneof | `oneof` is used where channels or types will be added in the future |
| Avoiding breaking changes | The design does not break existing clients when extended in the future |

### 3.5. Mechanical verification with buf (run it before the visual review)

Visually checking comment consistency and naming cannot catch wire compatibility breaks. In a repo with buf (a `buf.yaml` exists), always run the following and include the results in the review report.

```bash
# lint (naming conventions / style)
buf lint

# detect format drift (with --exit-code for a CI-equivalent check if this is for a commit)
buf format --diff --exit-code

# wire breaking check - the base is origin/$BASE decided in Step 1
buf breaking --against ".git#branch=origin/$BASE"
```

Guidelines for judging:

- If `buf breaking` finds 0 against the base, that PR alone is wire safe.
- If the base is not main (a chain PR), also running `--against .git#branch=main` shows the breaking changes when the whole chain is stacked on main. Violations that appear here are often caused by a downstream PR (a revert, for example), so always separate whether they are inside this PR's diff or come from a downstream PR, and report that (in the per-scope summary of Step 4).
- Missing `reserved`, deleted enum values, changed field types and so on are detected mechanically by the breaking check, so cross-check them against the visual "Need for reserved" check.

### 4. Report the results

Report in the following format. For each finding, always state "Applies to: inside the PR diff / pre-existing on main (outside the diff)":

````markdown
## Proto Review result

### Problems

**1. [Title of the problem] (severity: high/medium/low, applies to: inside the PR diff / pre-existing on main)**

[Explanation]

```protobuf
// Current
[current code]

// Proposal
[proposed fix]
```

### No problems

| Aspect | Verdict |
|------|------|
| [check item] | OK |
| ... | ... |
````

It is easier to read if inside/outside the diff is summarized at the end:

```markdown
### Summary by scope

- **Inside this PR's diff (fix recommended)**: 1, 2, 4
- **Pre-existing on main (outside the diff -> candidates for a separate issue)**: 3, 5
```

If there are no problems, show only the "No problems" section.

---
name: pict
description: "Generate matrices with three or more axes (test cases, environments, permissions) with Microsoft PICT instead of writing them by hand: model file, constraints, pairwise versus 3-way, install. Use when a table of combinations over several axes is about to be written by hand. Requirements: pict (built with git, make, g++). Triggers: pict, pairwise, combinatorial testing, generate a matrix, combination conditions, ペアワイズ, 組み合わせテスト, マトリクス生成, 組み合わせ条件."
---

# Generate combinations with PICT

Do not write out a matrix with three or more axes by hand. Write the parameters and constraints in a model file and have `pict <model>` generate it. Hand-written tables invariably miss combinations, let impossible combinations in, and need a full rewrite when an axis is added.

## Procedure

- This is not limited to test case design. It covers anything that can be expressed as axes x values: an environment matrix (env x region x protocol), a permission matrix (role x action x resource), and so on
- A model is a list of `Parameter: value, value, ...` lines, optional sub-models, and constraints, in that order. Impossible combinations are excluded with `IF [A] = "x" THEN [B] <> "y";`. Being able to write constraints is the difference from a hand-written table, so do not delete rows from the generated result by hand; write the constraint in the model
- The default is pairwise (2-way). Make only the axes whose interactions worry you denser with a sub-model such as `{ A, B, C } @ 3`. Raising the whole model with `/o:3` comes after that, and it is for models without such a sub-model (with one, the order must not exceed the number of sub-models plus the remaining parameters, otherwise pict stops with an input error)
- Keep the model file in the repo as a deliverable. If only the generated table is kept, it cannot be regenerated the next time an axis is added
- At order N, pict covers interactions between up to N factors (pairwise covers 2). Bugs in boundary values, state transitions and order dependence are not caught at any order, so design for those separately

## Example

Save as `model.txt`:

```text
OS: windows, linux, macos
Browser: chrome, firefox, safari
Role: admin, member, guest
Region: us, eu, jp

{ OS, Browser, Role } @ 3

IF [OS] <> "macos" THEN [Browser] <> "safari";
```

Generate, tab-separated with a header row:

```bash
pict model.txt
```

- This covers every valid `OS` x `Browser` x `Role` triple (21 of them, safari only on macos) and all pairs of the other axes
- Without the sub-model line, `pict model.txt /o:3` raises every axis to 3-way coverage and produces more rows than the pairwise default

## Install

Only when `pict` is missing. Needs git, make and g++, and `~/.local/bin` on `PATH`:

```bash
command -v pict >/dev/null || { d=$(mktemp -d) && git clone -q --depth 1 https://github.com/microsoft/pict "$d/pict" && make -C "$d/pict" && mkdir -p ~/.local/bin && cp "$d/pict/pict" ~/.local/bin/; }
```

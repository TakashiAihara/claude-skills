---
name: pict
description: "Generate matrices with three or more axes (test cases, environments, permissions) with Microsoft PICT instead of writing them by hand: how to write the model file, constraints, when to use pairwise versus 3-way, and how to install. Triggers: pict, pairwise, combinatorial testing, generate a matrix, combination conditions, ペアワイズ, 組み合わせテスト, マトリクス生成, 組み合わせ条件."
---

# Generate combinations with PICT

Do not write out a matrix with three or more axes by hand. Write the parameters and constraints in a model file and have `pict <model>` generate it.

## Procedure

- Do not write out a matrix with three or more axes by hand. Write the parameters and constraints in a model file and have `pict <model>` generate it. Hand-written tables invariably miss combinations, let impossible combinations in, and need a full rewrite when an axis is added
- This is not limited to test case design. It covers anything that can be expressed as axes x values: an environment matrix (env x region x protocol), a permission matrix (role x action x resource), and so on
- A model is a list of `Parameter: value, value, ...` lines, and impossible combinations are excluded with `IF [A] = "x" THEN [B] <> "y";`. Being able to write constraints is the difference from a hand-written table, so do not delete rows from the generated result by hand; write the constraint in the model
- The default is pairwise (2-way). Make only the axes whose interactions worry you denser with a sub-model such as `{ A, B, C } @ 3`. Raising the whole model to `/o:3` comes after that
- Keep the model file in the repo as a deliverable. If only the generated table is kept, it cannot be regenerated the next time an axis is added
- It only catches interactions between up to 2 factors. Bugs in boundary values, state transitions and order dependence are not caught, so design for those separately
- On a host where it is not installed: `git clone --depth 1 https://github.com/microsoft/pict && cd pict && make && cp pict ~/.local/bin/` (the only dependency is g++, and the build takes about 10 seconds)

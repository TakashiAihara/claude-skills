---
type: llm
focus: { source: file, path: model.txt }
---

PASS if model.txt is a declarative PICT-style model: it lists the four parameters with their values (a `Name: value, value, ...` line each) and expresses the two rules (Safari only on macOS, ApplePay only in Safari) as IF/THEN constraints.

FAIL if model.txt is a script (for example Python that loops over the values), a hand-typed table of chosen rows, or lacks the constraints.

---
type: regex
target: { source: file, path: docs/guide.md }
pattern: '^(<<<<<<<|=======|>>>>>>>)'
match: not_contains
flags: m
---

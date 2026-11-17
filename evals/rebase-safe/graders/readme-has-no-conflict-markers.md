---
type: regex
target: { source: file, path: README.md }
pattern: '^(<<<<<<<|=======|>>>>>>>)'
match: not_contains
flags: m
---

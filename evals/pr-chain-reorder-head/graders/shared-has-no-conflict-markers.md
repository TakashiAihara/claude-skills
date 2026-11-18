---
type: regex
target: { source: file, path: shared.txt }
pattern: '^(<<<<<<<|=======|>>>>>>>)'
match: not_contains
flags: m
---

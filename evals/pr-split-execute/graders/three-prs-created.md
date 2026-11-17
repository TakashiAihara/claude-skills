---
type: regex
target: { source: file, path: .gh-calls.log }
pattern: '^pr create '
match: count:3
flags: m
---

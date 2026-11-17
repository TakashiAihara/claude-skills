---
type: regex
target: { source: file, path: .gh-calls.log }
pattern: '^pr create (?![^\n]*--draft)'
match: not_contains
flags: m
---

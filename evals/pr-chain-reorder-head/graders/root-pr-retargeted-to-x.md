---
type: regex
target: { source: file, path: .gh-calls.log }
pattern: '^pr edit 11 (?=[^\n]*(?:--base|-B)[ =]feature/x(?: |$))'
flags: m
---

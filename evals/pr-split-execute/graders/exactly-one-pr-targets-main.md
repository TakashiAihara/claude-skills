---
type: regex
target: { source: file, path: .gh-calls.log }
pattern: '^pr create (?=[^\n]*(?:--base|-B)[ =]main(?: |$))'
match: count:1
flags: m
---

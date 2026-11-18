---
type: regex
target: { source: file, path: .git/packed-refs }
pattern: 'refs/heads/feature/login\b'
match: not_contains
---

---
type: regex
target: { source: file, path: .git/packed-refs }
pattern: 'refs/heads/feature/search\b'
match: not_contains
---

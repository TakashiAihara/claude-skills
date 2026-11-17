---
type: regex
target: trace
pattern: '"command":\s*"[^"]*git push[^"]*\s(--force(?!-with-lease)|-f)\s'
match: not_contains
---

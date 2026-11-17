---
type: regex
target: trace
pattern: '"command":\s*"[^"]*(git (push|commit|reset|rebase|restore|cherry-pick|checkout -b|switch -c|branch --no-track|branch -[a-zA-Z] )|gh pr create)'
match: not_contains
---

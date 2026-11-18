---
type: regex
target: { source: file, path: .tools/prs.json }
pattern: '"baseRefName": "main",\s*"headRefName": "feature/orders-part1",\s*"author": \{[^}]*\},\s*"isDraft": true'
---

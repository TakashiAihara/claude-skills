---
type: regex
target: { source: file, path: .tools/prs.json }
pattern: '"baseRefName": "feature/orders-part1",\s*"headRefName": "feature/orders-part2",\s*"author": \{[^}]*\},\s*"isDraft": true'
---

---
type: regex
target: { source: file, path: .tools/prs.json }
pattern: '"number": 40,(?:(?!"number":)[\s\S])*?"state": "CLOSED"'
---

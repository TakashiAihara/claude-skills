---
type: regex
target: trace
pattern: '"command":\s*"(?:[^"\\]|\\.)*(?:(?<!\w)|(?<=\\[nrt]))git(?:\s+(?:-C|-c|--git-dir|--work-tree)[ =](?:\\"[^"\\]*\\"|\S+))*\s+push\b(?:[^";&|\\]|\\[^n])*?\s(?:--force(?![-\w])|-[a-zA-Z]*f[a-zA-Z]*|\+[^\s"\\]+)(?=[\s"\\;&|])'
match: not_contains
---

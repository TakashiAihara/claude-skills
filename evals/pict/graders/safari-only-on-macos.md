---
type: regex
target: { source: file, path: matrix.tsv }
pattern: '^Safari\t(Windows|Linux)\t'
match: not_contains
flags: m
---

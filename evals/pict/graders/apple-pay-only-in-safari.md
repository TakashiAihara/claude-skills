---
type: regex
target: { source: file, path: matrix.tsv }
pattern: '^(Chrome|Firefox|Edge)\t[^\t]*\t[^\t]*\tApplePay\r?$'
match: not_contains
flags: m
---

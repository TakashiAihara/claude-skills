---
type: regex
target: { source: file, path: matrix.tsv }
pattern: '^(?=[\s\S]*^[^\t]*\tWindows\t[^\t]*\tCard\r?$)(?=[\s\S]*^[^\t]*\tWindows\t[^\t]*\tPayPal\r?$)(?=[\s\S]*^[^\t]*\tWindows\t[^\t]*\tKonbini\r?$)(?=[\s\S]*^[^\t]*\tmacOS\t[^\t]*\tCard\r?$)(?=[\s\S]*^[^\t]*\tmacOS\t[^\t]*\tPayPal\r?$)(?=[\s\S]*^[^\t]*\tmacOS\t[^\t]*\tKonbini\r?$)(?=[\s\S]*^[^\t]*\tLinux\t[^\t]*\tCard\r?$)(?=[\s\S]*^[^\t]*\tLinux\t[^\t]*\tPayPal\r?$)(?=[\s\S]*^[^\t]*\tLinux\t[^\t]*\tKonbini\r?$)'
flags: m
---

---
type: regex
target: { source: file, path: .gh-calls.log }
pattern: '^pr create (?=[^\n]*(?:--head|-H)[ =](\S+))[^\n]*\n(?:[^\n]*\n)*?pr create (?=[^\n]*(?:--base|-B)[ =]\1(?: |$))(?=[^\n]*(?:--head|-H)[ =](\S+))[^\n]*\n(?:[^\n]*\n)*?pr create (?=[^\n]*(?:--base|-B)[ =]\2(?: |$))'
flags: m
---

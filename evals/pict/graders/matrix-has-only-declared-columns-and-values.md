---
type: regex
target: { source: file, path: matrix.tsv }
pattern: '^Browser\tOS\tLocale\tPayment(?:\r?\n(?:Chrome|Firefox|Edge|Safari)\t(?:Windows|macOS|Linux)\t(?:en-US|ja-JP|de-DE)\t(?:Card|PayPal|Konbini|ApplePay))+(?:\r?\n)*$'
---

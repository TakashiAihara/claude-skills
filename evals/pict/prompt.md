---
tags: [generation]
max_turns: 25
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit, Skill]
---

I need a test matrix for our checkout page. The axes are Browser (Chrome, Firefox, Edge, Safari), OS (Windows, macOS, Linux), Locale (en-US, ja-JP, de-DE) and Payment (Card, PayPal, Konbini, ApplePay). Safari only exists on macOS, and ApplePay only works in Safari. Write the matrix to matrix.tsv (tab-separated, header row Browser, OS, Locale, Payment), and keep whatever you generated it from as model.txt in this directory so I can regenerate the matrix when we add an axis. I can only run about 40 cases by hand, so keep it small without losing coverage of the axis pairs that can actually occur.

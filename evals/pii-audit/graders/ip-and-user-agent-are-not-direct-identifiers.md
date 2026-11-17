---
type: llm
focus: { source: file, path: personal-information.md }
---

PASS if IP address and User-Agent are classified as personal-related information / online identifiers (the category for IP addresses, cookie IDs and user agents), and customer_email is classified as a direct identifier.

FAIL if IP address or User-Agent is classified as a direct identifier or as a quasi-identifier, or if the items are not classified at all.

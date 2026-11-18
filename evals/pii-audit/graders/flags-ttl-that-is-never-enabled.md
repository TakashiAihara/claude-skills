---
type: llm
focus: { source: file, path: personal-information.md }
---

The orders table stores an `expires_at` attribute, but the Terraform for the table does not enable DynamoDB TTL, so nothing is deleted automatically.

PASS if the document says for the orders table that `expires_at` exists but TTL is not enabled (or that nothing is deleted automatically).

FAIL if it lists `expires_at` as a working retention or deletion mechanism, or never mentions the gap.

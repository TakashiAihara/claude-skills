---
type: llm
focus: last_message
---

PASS if the proposed plan keeps the billing tests in the same PR as the billing code they test (or in the PR that follows directly and builds on it only when the reply explains why), and does not defer all tests to a final "tests" PR.

FAIL if the plan puts all tests in a separate last PR, or never says where the tests go.

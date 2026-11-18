---
type: llm
focus: { source: file, path: personal-information.md }
---

The create-order handler logs the customer's email address and the caller's IP address (x-forwarded-for) to the application log, and the load balancer has access logging enabled.

PASS if the document identifies that email and/or IP address reach the application logs or the load balancer access logs, and treats those logs as a store in scope.

FAIL if logs are not mentioned as holding personal information.

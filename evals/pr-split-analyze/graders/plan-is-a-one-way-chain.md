---
type: llm
focus: last_message
---

The branch has six commits in this order: database migrations, infrastructure (Terraform), billing services, API routes, tests plus docs, and a generated lockfile.

PASS if the reply proposes a split into two or more PRs where every PR is listed with its scope (files or commits), what it depends on and what its base is, the dependencies run in one direction (PR 1 -> PR 2 -> PR 3, each later PR based on the previous one), and the order puts migrations and infrastructure before the application code.

FAIL if the reply is only general advice with no concrete PR list, if the PRs are not ordered by dependency, or if the PRs are independent siblings that all target main.

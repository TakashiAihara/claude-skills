---
tags: [git]
max_turns: 50
timeout_seconds: 600
allowed_tools: [Bash, Read, Glob, Grep, Skill]
---

I've approved the split plan for PR #40 (branch feature/orders, base main). Please carry it out:

- PR 1 (branch feature/orders-part1): everything under db/ and infra/
- PR 2 (branch feature/orders-part2): src/orders/ and tests/orders/, based on PR 1
- PR 3 (branch feature/orders-part3): docs/orders.md, based on PR 2

Push the three part branches to origin and open them as a chain of draft PRs, and close #40 once all three exist (I approve that). We squash-merge here, so tell me how to merge the chain. Leave the last part checked out when you're done.

There is no network in this sandbox. `./.tools/gh` is an offline stand-in for the GitHub CLI that returns canned data and logs calls; use it wherever you would call gh.

---
tags: [git]
max_turns: 60
timeout_seconds: 600
allowed_tools: [Bash, Read, Glob, Grep, Edit, Write, Skill]
---

PRs #101, #102 and #103 in example/shop are a chain (main <- feature/alpha <- feature/beta <- feature/gamma). I verified all three locally on 2026-11-10: unit tests passed, nothing else was run, and CI has not run on them yet. Add a verification record for each PR as its own commit, following the docs/test-results convention in the repo (use the slugs alpha, beta and gamma). Keep the chain stacked and push all three branches; you may force-push these branches, nobody else uses them. Leave me on feature/gamma.

There is no network in this sandbox. `./.tools/gh` is an offline stand-in for the GitHub CLI that returns canned data and logs calls; use it wherever you would call gh.

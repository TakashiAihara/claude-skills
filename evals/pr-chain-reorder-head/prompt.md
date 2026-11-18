---
tags: [git]
max_turns: 60
timeout_seconds: 600
allowed_tools: [Bash, Read, Glob, Grep, Edit, Write, Skill]
---

I have a chain of PRs: main <- feature/a (#11) <- feature/b (#12) <- feature/c (#13). I want feature/x, which has been running off main on its own, underneath all of them, so the order becomes main <- feature/x <- feature/a <- feature/b <- feature/c, with the PRs pointing at the right bases. If rebasing hits a conflict in shared.txt, keep both sides' lines (one copy of each). You may force-push feature/a, feature/b and feature/c; nobody else uses them. Leave me on feature/c.

There is no network in this sandbox. `./.tools/gh` is an offline stand-in for the GitHub CLI that returns canned data and logs calls; use it wherever you would call gh.

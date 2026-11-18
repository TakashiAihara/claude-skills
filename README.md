# claude-skills

General-purpose Claude Code skills, published as the `skills` plugin of the `takashiaihara` marketplace.

| Skill | What it does |
|---|---|
| [animated-step-slides](skills/animated-step-slides/SKILL.md) | Single-file HTML slides for spec documents: each press of → moves a diagram one step, with checkers for fit and steps |
| [clean-branches](skills/clean-branches/SKILL.md) | Prune stale remote refs and delete merged and squash-merged local branches after confirmation |
| [pict](skills/pict/SKILL.md) | Generate combination matrices (test cases, environments, permissions) with Microsoft PICT instead of by hand |
| [pii-audit](skills/pii-audit/SKILL.md) | Inventory the personal information in a repo's data stores into personal-information.md (APPI / GDPR) |
| [pr-chain-reorder-head](skills/pr-chain-reorder-head/SKILL.md) | Insert a branch at the head of a PR chain and reconnect the chain with rebase --onto |
| [pr-chain-verify](skills/pr-chain-verify/SKILL.md) | Add a per-PR verification document to every PR in a chain with a cascade rebase |
| [pr-split-analyze](skills/pr-split-analyze/SKILL.md) | Analyze a large PR and propose a one-way chain of smaller PRs |
| [pr-split-execute](skills/pr-split-execute/SKILL.md) | Execute an approved PR split: backup, split branches, chained draft PRs, merge order |
| [proto-review](skills/proto-review/SKILL.md) | Review protobuf files for AIP compliance and wire safety, scoped to the PR diff, with buf checks |
| [rebase-safe](skills/rebase-safe/SKILL.md) | Rebase onto the base branch, auto-resolving documentation conflicts and asking about the rest |

## Install

As a Claude Code plugin (the skills are listed as `skills:<name>`, e.g. `skills:animated-step-slides`):

```bash
claude plugin marketplace add TakashiAihara/claude-skills
claude plugin install skills@takashiaihara
```

As plain skills for any agent that reads `SKILL.md`:

```bash
npx skills add TakashiAihara/claude-skills
```

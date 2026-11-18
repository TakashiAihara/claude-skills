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
| [skill-eval](skills/skill-eval/SKILL.md) | Write and run `claude plugin eval` cases that compare a skill with the same model without it, and read the scores |

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

## Evals

`evals/` holds one `claude plugin eval` case per skill (except animated-step-slides). Each case runs the same request with and without the plugin and scores the result; git cases build a throwaway repo with a local bare `origin` in `scaffold.sh`. The PR-chain and PR-split cases (`pr-chain-reorder-head`, `pr-chain-verify`, `pr-split-execute`) send their `gh` calls to an offline stand-in (`evals/_shared/gh`, which needs `python3` and `jq` on the host); the other git cases (including `clean-branches`) are git-only and do not use it. Graders check observable results with regex and file checks, and they cannot verify file contents inside git objects, so a few checks are presence-based (for example, a pushed branch ref exists).

```bash
TMPDIR="$HOME/evaltmp" claude plugin eval . --model sonnet --scaffold --trust-plugin --allow-tools Bash Write Edit --no-publish
```

- `--scaffold` runs the case scripts in `evals/*/scaffold.sh` as you; read them first.
- Linux: point `TMPDIR` outside `/tmp`, `/var/tmp`, `/dev/shm` and `/run/shm` (create the directory first). Otherwise the sandbox denies every Bash write in the run's workspace, and the git cases fail in both arms ([anthropics/claude-code#104631](https://github.com/anthropics/claude-code/issues/104631)).
- The trace graders are regular expressions over the recorded shell commands, not a shell parser: a command inside a quoted string (for example in `echo` or `grep`) can match, and unusual spellings (git global options, quoted `+refspec`) can slip past. Read a failing run's trace before trusting a score.
- Granting Bash needs a working sandbox (bubblewrap and socat on Linux). It does not start in an unprivileged container that cannot create a nested user namespace, nor when `~/.ssh` contains symlinks.

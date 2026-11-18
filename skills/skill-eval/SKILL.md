---
name: skill-eval
description: "Write and run `claude plugin eval` cases that measure whether a plugin's skills fire on realistic requests and do better than the same model without the plugin, then read the scores without over-reading them. Use before publishing skills, after changing a skill, or when eval scores look wrong (both arms fail the same way, scores of 0 with short runs). Triggers: skill eval, plugin eval, skill の効き目, eval 回して, skill を評価."
---

# Skill Eval

Measure a skill by running the same request with and without the plugin (`claude plugin eval`'s default with-without ablation) and comparing the scores.

Requirements: Claude Code with `claude plugin eval`; `git` 2.31 or later; on Linux, bubblewrap and socat for the Bash sandbox. A stand-in CLI written in Python also needs `python3` (and `jq` if it supports `--jq`).

## What the numbers mean

- A run's score is the weighted share of scored graders that passed (0 to 1). Graders marked with-only (such as `tool_used: Skill`) are reported as a firing indicator and do not enter the score.
- `with` and `without` are the mean scores over the runs of each arm; `Δ` is with minus without. Fired is how many with-arm runs invoked the skill.
- What a result tells you:
  - Fired below the run count: the description does not trigger on that request.
  - Positive Δ: the behaviors the baseline misses are the skill's contribution. Name them from the failed graders, not from the number.
  - Δ of 0 with both arms at 1.00: the case is easy enough that the model solves it alone. It does not show the skill is useless; add a harder scenario before concluding.
  - Both arms failing the same graders in the same way: suspect the environment or the graders before the skill (see Diagnose).
- With 3 runs per arm, a difference of about 0.1 is within noise. A grader that checks the skill's own output format lowers the baseline for format alone; say so when reporting.

## Workflow

### 1. Lay out one case per skill

```text
evals/
  _shared/            # stand-ins shared by cases (optional)
  <case>/
    prompt.md         # frontmatter: allowed_tools, max_turns, timeout_seconds; body: the request
    case.yaml         # context.scaffold_script (optional)
    scaffold.sh       # builds the situation before the run (runs as you, outside the sandbox)
    graders/*.md      # one grader per file
```

- Check the format against `claude plugin eval --help` and `claude plugin eval init --bare <name>` (run it in a scratch copy, not in the repo); grader types are `regex`, `tool_used`, `tool_order`, `file_exists`, `llm` and `baseline`, and there are no custom-code graders.
- Add `evals/results/` to `.gitignore`.

### 2. Write the request

- A realistic request in the user's words that does not name the skill; both arms get the same text.
- Pre-approve destructive steps in the request ("you're cleared to force-push this branch") so the run can finish without a human, and give any facts the skill would otherwise ask for (scope, output path).
- When the scenario needs a name the grader must find (branch names, output paths), state it in the request.

### 3. Build the situation in `scaffold.sh`

- Create a throwaway git repo in the working directory with a local bare remote (`git init --bare .remote/origin.git`), exclude `.remote/` in `.git/info/exclude`, and set a fixed author (`dev@example.com`).
- Network CLIs (`gh` and the like) get an offline stand-in copied into the workspace (for example `.tools/gh`) that logs each call and records the resulting state in a JSON file (`.tools/prs.json`): created PRs with head, base and draft, closed PRs, edited bases. The request tells both arms to use it.
- Use neutral fixture names (`example/shop`, `example.com`); nothing from a real project.

### 4. Write graders on observable results

- Prefer state over transcript text: files in the workspace, remote refs (`.remote/origin.git/refs/heads/<branch>` exists after a push to a bare repo whose refs were packed), and the stand-in's recorded JSON.
- `regex` on `target: trace` reads JSON lines where shell commands appear as `"command": "..."` with inner quotes escaped. Match escape-aware, for example `"command":\s*"(?:[^"\\]|\\.)*git push(?:[^"\\]|\\.)*--force-with-lease=(?:\\")?[^\s:"\\]+:[^\s"\\]`. A plain `[^"]*` stops at the first escaped quote and silently misses.
- Allow flags the skill inserts (`git rebase --no-update-refs --onto`, `git -c x=y rebase`); a pattern written against an older skill text fails the with-arm only.
- Use one `tool_used: Skill` grader per case as the with-only firing indicator, and `llm` graders only for judgment the regex cannot express.
- Trace regexes are not a shell parser: a command inside a quoted string can match, and unusual spellings can slip past. Prefer state checks; document the limit when you rely on trace regexes.

### 5. Check the graders before running

- Run every regex against hand-written positive and negative samples (Python `re`; the harness uses JavaScript `RegExp`, so check the important ones in Node too).
- Parse every grader's frontmatter as YAML, and run `claude plugin validate .`.
- Run the scaffold once by hand and confirm the state the graders expect is absent before the run.

### 6. Run

Smoke one case first, then the suite:

```bash
mkdir -p "$HOME/evaltmp"
TMPDIR="$HOME/evaltmp" claude plugin eval . --case <case> --runs 1 --model sonnet --scaffold --trust-plugin --allow-tools Bash Write Edit --no-publish --keep-temp
TMPDIR="$HOME/evaltmp" claude plugin eval . --runs 3 -j 2 --model sonnet --scaffold --trust-plugin --allow-tools Bash Write Edit --no-publish --max-cost-usd 20 --json evals/results/full.json
```

- `--scaffold` runs the case scripts as you; read them first.
- Cost is shown as an API-price estimate; on a subscription login it consumes the plan's usage, not money.

### 7. Read the results per grader

- Summarize per case: with, without, Δ, fired, and the failed graders counted per arm. The JSON has `cases[].aggregates` and `cases[].arms.{with,without}[].graders[]`.
- A grader failing in the with-arm on every run is usually a grader that no longer matches the skill; compare it with the commands in a kept trace before editing the skill.
- After changing a skill, re-read the graders that match its commands.

## Diagnose

| Symptom | Cause | Fix |
|---|---|---|
| Every Bash write fails with `Read-only file system`, both arms score the same, runs end in a few turns | The run workspace is under `/tmp`, which the generated sandbox policy denies (anthropics/claude-code#104631) | Point `TMPDIR` outside `/tmp`, `/var/tmp`, `/dev/shm`, `/run/shm` |
| The run refuses to start when Bash is granted, mentioning `~/.ssh` | The sandbox cannot exclude symlinks in `~/.ssh` | Run on a host or user without symlinks there |
| `apply-seccomp: write /proc/self/setgroups ... Permission denied` on every Bash call | Unprivileged container that cannot create a nested user namespace | Run on a VM, WSL2 or bare host |
| `sandbox required but unavailable: ... socat not installed` | Missing sandbox dependency | Install `socat` (and `bubblewrap`) |
| Trace paths in the JSON point to deleted directories | Run directories are removed after the run | Rerun the case with `--keep-temp`; remove the kept directories afterwards (`chmod -R u+rwX <dir> && rm -rf <dir>`) |

## Report

- A table of case, with, without, Δ and fired, the run count, model and Claude Code version, and the commit the suite ran on.
- The behaviors the baseline missed, from the failed graders.
- What the scores cannot show (noise at this run count, format graders, cases where both arms tie).

---
name: skill-eval
description: "Use when writing or running `claude plugin eval` cases for a plugin's skills, checking whether a skill fires on realistic requests and beats the same model without the plugin, or when eval scores look wrong (both arms fail the same way, scores of 0 with short runs). Triggers: skill eval, plugin eval, skill の効き目, eval 回して, skill を評価."
---

# Skill Eval

Measure a skill by running the same request with and without the plugin (`claude plugin eval`'s default with-without ablation) and comparing the scores.

Requirements: Claude Code 2.1.269 or later (`claude plugin eval`); `git` 2.31 or later if git is installed (the skill under test may need newer, e.g. 2.38 for `--no-update-refs`); on Linux, bubblewrap and socat for the Bash sandbox. A stand-in CLI written in Python also needs `python3` (and `jq` if it supports `--jq`).

## What the numbers mean

- A run's score is the weighted share of scored graders that passed (0 to 1). Graders marked with-only (such as `tool_used: Skill`) are reported as a firing indicator and do not enter the score.
- `with` and `without` are the mean scores over the runs of each arm; `Δ` is with minus without. The CLI has no "fired" column: count it yourself as the with-arm runs in which the with-only `tool_used: Skill` grader passed (select it by its grader name, since other with-only graders are also `scored: false`).
- What a result tells you:
  - Fired below the run count: the description may not trigger on that request, or the request did not need the skill; check which before rewriting the description.
  - Positive Δ: the behaviors the baseline misses are the skill's contribution. Name them from the failed graders, not from the number.
  - Δ of 0 with both arms at 1.00: the case is easy enough that the model solves it alone. It does not show the skill is useless; add a harder scenario before concluding.
  - Negative Δ: the skill adds steps, asks instead of acting, or a grader checks something the skill does differently; read the with-arm's failed graders before trusting the sign.
  - Both arms failing the same graders in the same way: suspect the environment or the graders before the skill (see Diagnose).
- With N equally weighted scored graders a run's score moves in steps of 1/N (with weights, in steps of each grader's share), and the docs call a single run noisy; with 3 runs per arm, treat a difference of about one grader's weight as noise (an observation, not a documented threshold). A grader that checks the skill's own output format lowers the baseline for format alone; say so when reporting.

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

- `case.yaml` needs `schema_version: "1.1"` and `name` besides `context.scaffold_script`; `init --bare` does not create it.
- Put `Skill` in `allowed_tools` of every case, or the skill cannot fire; `Bash`, `Write` and `Edit` also need the operator grant `--allow-tools` on the command line.
- Check the format against `claude plugin eval --help` and `claude plugin eval init --bare <name>` (run it in a scratch copy, not in the repo); grader types are `regex`, `tool_used`, `tool_order`, `file_exists`, `llm` and `baseline`, and there are no custom-code graders.
- Add `evals/results/` to `.gitignore`.

### 2. Write the request

- A realistic request in the user's words that does not name the skill; both arms get the same text.
- Pre-approve destructive steps in the request ("you're cleared to force-push this branch") so the run can finish without a human, and give any facts the skill would otherwise ask for (scope, output path).
- When the scenario needs a name the grader must find (branch names, output paths), state it in the request.

### 3. Build the situation in `scaffold.sh`

- Create a throwaway git repo in the working directory with a local bare remote (`git init --bare .remote/origin.git`), exclude `.remote/` and `.tools/` in `.git/info/exclude`, set a fixed author (`dev@example.com`) and `commit.gpgsign false`, and finish with `git -C .remote/origin.git pack-refs --all` so that a ref file present after the run was written by a push during it.
- Name the script in `case.yaml` (`context.scaffold_script`; it is not discovered by file name). Each run gets a fresh workspace and the scaffold runs again for it, so state left by one run cannot satisfy another run's graders.
- The scaffold runs with a minimal environment: `HOME` is the run's temporary home (no gitconfig, so set `user.name` / `user.email` in the repo), it has a 120-second limit, and a non-zero exit scores the run 0. The run cannot read the eval directory, so copy stand-ins in (`cp "$(dirname "$0")/../_shared/gh" .tools/gh`).
- Network CLIs (`gh` and the like) get an offline stand-in copied into the workspace (for example `.tools/gh`) that logs each call and records the resulting state in a JSON file (`.tools/prs.json`): created PRs with head, base and draft, closed PRs, edited bases. The request tells both arms to use it.
- Use neutral fixture names (`example/shop`, `example.com`); nothing from a real project.

### 4. Write graders on observable results

- `file_exists` sees only files Claude created during the run. It suits "this ref exists after a push", not "a file the scaffold made is gone": `exists: false` on a scaffold-made path passes whether or not it was removed. Read contents with `regex` and `target: { source: file, path: <path> }`.
- Prefer state over transcript text: files in the workspace (read with `target: { source: file, path }`), remote refs (`.remote/origin.git/refs/heads/<branch>` is written by a push after the scaffold packed the existing refs, as long as nothing packs them again before grading), and the stand-in's recorded JSON.
- `regex` on `target: trace` reads JSON lines where shell commands appear as `"command": "..."` with inner quotes escaped. Match escape-aware, for example `"command":\s*"(?:[^"\\]|\\.)*git push(?:[^"\\]|\\.)*--force-with-lease=(?:\\")?[^\s:"\\]+:[^\s"\\]`. A plain `[^"]*` stops at the first escaped quote and silently misses.
- Allow flags the skill inserts (`git rebase --no-update-refs --onto`, `git -c x=y rebase`); a pattern written against an older skill text fails the with-arm only.
- Every case needs at least one scored grader; a case with only the firing indicator has no score.
- Use one `tool_used: Skill` grader per case as the firing indicator (it is excluded from the score automatically), and `llm` graders only for judgment the regex cannot express:

```text
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?<skill name>"'
---
```
- Trace regexes are not a shell parser: a command inside a quoted string can match, and unusual spellings can slip past. Prefer state checks; document the limit when you rely on trace regexes.

### 5. Check the graders before running

- Run every regex against hand-written positive and negative samples in Node (`new RegExp(pattern, flags)`), since the harness uses JavaScript regex. Put flags in `flags: i` / `flags: m`, not inline `(?i)`, and single-quote patterns in the frontmatter so YAML keeps `\s` and `\\`.
- Parse every grader's frontmatter as YAML, and run `claude plugin validate .`.
- Run the scaffold once by hand in an empty temporary directory, in a subshell so your shell stays in the plugin root (`(d=$(mktemp -d) && cd "$d" && bash /abs/path/to/plugin/evals/<case>/scaffold.sh && ls -a)`; never in the plugin repo, where it would rewrite that repo's git config), and confirm the state the graders expect is absent before the run.

### 6. Run

Smoke one case first, then the suite:

```bash
mkdir -p "$HOME/evaltmp"
TMPDIR="$HOME/evaltmp" claude plugin eval . --case <case> --runs 1 --model sonnet --scaffold --trust-plugin --allow-tools Bash Write Edit --no-publish --keep-temp
TMPDIR="$HOME/evaltmp" claude plugin eval . --runs 3 -j 2 --model sonnet --scaffold --trust-plugin --allow-tools Bash Write Edit --no-publish --max-cost-usd 20 --json evals/results/full.json
```

- `--scaffold` runs the case scripts as you; read them first.
- The suite is cases x runs x 2 arms Claude runs, plus judge calls for every `llm` / `baseline` grader. With `--json` the run prints no progress or summary table; read the JSON afterwards.
- `--max-cost-usd` stops the run with exit 2 and `partial: true`; do not read a partial result as a score.
- Cost is shown as an API-price estimate; on a subscription login it consumes the plan's usage, not money.

### 7. Read the results per grader

- Check every run's `error` first: a run that ended on an API or harness error scores 0 with no grader results and is not marked partial. Rerun those before summarizing.
- Summarize per case: with, without, Δ, fired, and the failed graders counted per arm. The JSON has `cases[].aggregates` and `cases[].arms.{with,without}[].graders[]`.
- A grader failing in the with-arm on every run is usually a grader that no longer matches the skill; compare it with the commands in a kept trace before editing the skill.
- After changing a skill, re-read the graders that match its commands.

## Diagnose

The error texts below were observed on Linux runs (WSL2 and LXC containers), not quoted from the docs.

| Symptom | Cause | Fix |
|---|---|---|
| Every Bash write fails with `Read-only file system`, both arms score the same, runs end in a few turns | The run workspace is under `/tmp`, which the generated sandbox policy denies (anthropics/claude-code#104631, open; reported on 2.1.304 to 2.1.325) | Point `TMPDIR` outside `/tmp`, `/var/tmp`, `/dev/shm` and `/run/shm` (2.1.310 added the last); a directory under `$HOME` worked. Remove this row once the issue is fixed |
| The run refuses to start when Bash is granted, mentioning `~/.ssh` | The sandbox cannot exclude symlinks in `~/.ssh` | Run on a host or user without symlinks there |
| `apply-seccomp: write /proc/self/setgroups ... Permission denied` on every Bash call | Unprivileged container that cannot create a nested user namespace | Run on a VM, WSL2 or bare host |
| `sandbox required but unavailable: ... socat not installed` | Missing sandbox dependency | Install `socat` (and `bubblewrap`) |
| Trace paths in the JSON point to deleted directories | Run directories are removed after the run | Rerun the case with `--keep-temp`; remove the kept directories afterwards (`chmod -R u+rwX <dir> && rm -rf <dir>`) |

## Report

- One line saying what the numbers are (each score is the weighted share of graders met, 0 to 1; Δ is with minus without), placed with the table so a reader does not have to ask.
- A table of case, with, without, Δ and fired, the run count, model and Claude Code version, and the commit the suite ran on (commit the skill edits first, so the commit describes what was measured).
- The behaviors the baseline missed, from the failed graders.
- What the scores cannot show (noise at this run count, format graders, cases where both arms tie).

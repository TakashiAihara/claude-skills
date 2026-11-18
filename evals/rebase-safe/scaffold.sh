#!/usr/bin/env bash
# feature/docs-refresh edits docs/guide.md (line 3 conflicts with main, line 25 does not) and
# README.md (line 1 conflicts, line 10 does not). Both branch and main are pushed to a local origin.
set -eu
export GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
git init -q -b main .
git config user.name dev
git config user.email dev@example.com
git config commit.gpgsign false
git init -q --bare -b main .remote/origin.git
printf '.remote/\n' >> .git/info/exclude
git remote add origin "$PWD/.remote/origin.git"

commit() { git add -A && git commit -q -m "$1"; }
# sub FILE LINE TEXT: replace one line of FILE
sub() { awk -v n="$2" -v t="$3" 'NR==n {print t; next} {print}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

mkdir -p docs src
{ echo "# Operations guide"; echo; echo "Timeout: 10 seconds"; for i in $(seq 4 24); do echo "Section note $i"; done; echo "Retry budget: 3 attempts"; for i in $(seq 26 30); do echo "Appendix line $i"; done; } > docs/guide.md
{ echo "Shop service"; for i in $(seq 2 9); do echo "Readme line $i"; done; echo "Contributing: open an issue first"; echo "Readme line 11"; echo "Readme line 12"; } > README.md
echo "print('shop')" > src/app.py
commit "chore: init"
git push -q -u origin main
git remote set-head origin main

git switch -q -c feature/docs-refresh
sub docs/guide.md 3 "Timeout: 45 seconds"
sub docs/guide.md 25 "Retry budget: 5 attempts"
commit "docs: raise timeout and retry budget"
sub README.md 1 "Shop service (docs refresh)"
sub README.md 10 "Contributing: see CONTRIBUTING.md"
commit "docs: refresh readme"
git push -q -u origin feature/docs-refresh

git switch -q main
sub docs/guide.md 3 "Timeout: 30 seconds (updated by platform team)"
commit "docs: platform timeout"
sub README.md 1 "Shop service (platform edition)"
commit "docs: readme title"
git push -q origin main
git switch -q feature/docs-refresh
git -C .remote/origin.git pack-refs --all
git pack-refs --all

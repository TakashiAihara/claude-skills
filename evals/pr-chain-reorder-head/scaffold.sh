#!/usr/bin/env bash
# Chain main <- feature/a (#11) <- feature/b (#12) <- feature/c (#13), plus feature/x off main.
# x and a both append to shared.txt, so rebasing a onto x conflicts and rewrites a's commit
# (a plain `git rebase feature/a` on b would then replay the old a commit a second time).
# ./.tools/gh is an offline stand-in for gh.
set -eu
export GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
git init -q -b main .
git config user.name dev
git config user.email dev@example.com
git config commit.gpgsign false
git init -q --bare -b main .remote/origin.git
printf '.remote/
.tools/
.gh-calls.log
.gh-next
' >> .git/info/exclude
git remote add origin "$PWD/.remote/origin.git"

commit() { git add -A && git commit -q -m "$1"; }

mkdir -p .tools
cp "$(dirname "$0")/../_shared/gh" .tools/gh
chmod +x .tools/gh
cat > .tools/prs.json <<'JSON'
{"next_pr": 14, "prs": {
 "11": {"number": 11, "title": "refactor: split config loading", "baseRefName": "main", "headRefName": "feature/a", "author": {"login": "dev"}},
 "12": {"number": 12, "title": "refactor: typed settings", "baseRefName": "feature/a", "headRefName": "feature/b", "author": {"login": "dev"}},
 "13": {"number": 13, "title": "refactor: remove legacy loader", "baseRefName": "feature/b", "headRefName": "feature/c", "author": {"login": "dev"}}
}}
JSON

printf 'base line\n' > shared.txt
echo "# shop" > README.md
commit "chore: init"
git push -q -u origin main
git remote set-head origin main

git switch -q -c feature/x main
echo "x" > x.txt
echo "line from X" >> shared.txt
commit "feat: x"
git push -q -u origin feature/x

git switch -q -c feature/a main
echo "a" > a.txt
echo "line from A" >> shared.txt
commit "refactor: a"
git push -q -u origin feature/a
git switch -q -c feature/b feature/a
echo "b" > b.txt
commit "refactor: b"
git push -q -u origin feature/b
git switch -q -c feature/c feature/b
echo "c" > c.txt
commit "refactor: c"
git push -q -u origin feature/c
git switch -q main
git -C .remote/origin.git pack-refs --all
git pack-refs --all

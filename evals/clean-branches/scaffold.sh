#!/usr/bin/env bash
# Builds ./ as a clone-like repo with a local bare origin: feature/login was merged with a
# merge commit, feature/search (3 commits) was squash-merged, feature/export-wip is unmerged.
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

echo "# shop" > README.md
commit "chore: init"
git push -q -u origin main
git remote set-head origin main

git switch -q -c feature/login
echo "login page" > login.txt
commit "feat: login page"
git switch -q main
git merge -q --no-ff -m "Merge pull request #11 from feature/login" feature/login

git switch -q -c feature/search main~1
echo "search: parse query" > search.txt
commit "feat(search): parse query"
echo "search: rank results" >> search.txt
commit "feat(search): rank results"
echo "search: highlight matches" >> search.txt
commit "feat(search): highlight matches"
git switch -q main
git merge -q --squash feature/search
git commit -q -m "feat: search (#12)"

git switch -q -c feature/export-wip main
echo "export: csv header" > export.txt
commit "wip(export): csv header"
echo "export: csv rows" >> export.txt
commit "wip(export): csv rows"
git switch -q main

git push -q origin main
git pack-refs --all

#!/usr/bin/env bash
# Chain main <- feature/alpha (#101) <- feature/beta (#102) <- feature/gamma (#103), all pushed,
# with an existing docs/test-results convention. ./.tools/gh is an offline stand-in for gh.
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
{"next_pr": 104, "prs": {
 "101": {"number": 101, "title": "feat: search index", "baseRefName": "main", "headRefName": "feature/alpha", "author": {"login": "dev"}, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN"},
 "102": {"number": 102, "title": "feat: search ranking", "baseRefName": "feature/alpha", "headRefName": "feature/beta", "author": {"login": "dev"}, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN"},
 "103": {"number": 103, "title": "feat: search highlighting", "baseRefName": "feature/beta", "headRefName": "feature/gamma", "author": {"login": "dev"}, "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN"}
}}
JSON

mkdir -p docs/test-results
cat > docs/test-results/export-csv.md <<'MD'
# Test result: #77 feat: csv export

- **Test date**: 2026-09-30
- **Environment**: local
- **Method**: unit tests

## Test items

| # | Test | Means | Expected | Result |
|---|------|-------|----------|--------|
| 1 | Export of 3 rows | `npm test` | 3 lines | pass |
MD
echo "# shop" > README.md
commit "chore: init"
git push -q -u origin main
git remote set-head origin main

git switch -q -c feature/alpha main
echo "index" > alpha.txt
commit "feat: search index"
git push -q -u origin feature/alpha
git switch -q -c feature/beta feature/alpha
echo "ranking" > beta.txt
commit "feat: search ranking"
git push -q -u origin feature/beta
git switch -q -c feature/gamma feature/beta
echo "highlighting" > gamma.txt
commit "feat: search highlighting"
git push -q -u origin feature/gamma
git switch -q main
git -C .remote/origin.git pack-refs --all
git pack-refs --all

#!/usr/bin/env bash
# feature/billing: 6 commits (migration, infra, service, API, tests+docs, lockfile) off main.
# Non-lockfile diff is 2000 lines, the generated lockfile adds 4000 more.
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
# gen FILE LINES TEMPLATE: write LINES lines, %d in TEMPLATE is the line number
gen() { mkdir -p "$(dirname "$1")"; awk -v n="$2" -v t="$3" 'BEGIN { for (i = 1; i <= n; i++) { s = t; gsub(/%d/, i, s); print s } }' > "$1"; }

echo "# shop" > README.md
printf '{\n  "name": "shop",\n  "version": "1.0.0"\n}\n' > package.json
commit "chore: init"
git push -q -u origin main
git remote set-head origin main

git switch -q -c feature/billing
gen db/migrations/010_invoices.sql 220 "ALTER TABLE invoices ADD COLUMN col_%d integer NOT NULL DEFAULT 0;"
gen db/migrations/011_payments.sql 180 "ALTER TABLE payments ADD COLUMN col_%d integer NOT NULL DEFAULT 0;"
commit "feat(db): invoices and payments tables"
gen infra/billing_queue.tf 150 '  setting_%d = "value_%d"'
commit "feat(infra): billing queue and alarms"
for f in invoice payment refund ledger; do gen "src/billing/$f.ts" 200 "export const ${f}Rule%d = (x: number) => x + %d;"; done
commit "feat(billing): invoice, payment, refund and ledger services"
gen src/api/billing_routes.ts 150 "router.get('/billing/route%d', handler%d);"
commit "feat(api): billing routes"
for f in invoice payment refund ledger; do gen "tests/billing/$f.test.ts" 100 "it('${f} case %d', () => expect(${f}Rule%d(1)).toBe(%d + 1));"; done
gen docs/billing.md 100 "Billing rule %d is documented here."
commit "test+docs: billing tests and documentation"
gen package-lock.json 4000 '    "pkg-%d": { "version": "1.0.%d" },'
commit "chore: update lockfile"
git push -q -u origin feature/billing
git pack-refs --all

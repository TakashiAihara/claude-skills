#!/usr/bin/env bash
# feature/orders touches db/infra, src+tests and docs. ./.tools/gh is an offline stand-in for gh
# that logs every call to ./.gh-calls.log and knows PR #40 (base main).
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
{"next_pr": 41, "prs": {"40": {"number": 40, "title": "feat: orders", "baseRefName": "main", "headRefName": "feature/orders", "author": {"login": "dev"}, "state": "OPEN"}}}
JSON

echo "# shop" > README.md
commit "chore: init"
git push -q -u origin main
git remote set-head origin main

git switch -q -c feature/orders
mkdir -p db/migrations infra src/orders tests/orders docs
printf 'CREATE TABLE orders (id bigint PRIMARY KEY, customer_id bigint NOT NULL);\n' > db/migrations/020_orders.sql
printf 'resource "aws_sqs_queue" "orders" { name = "orders" }\n' > infra/orders_queue.tf
commit "feat(db): orders table and queue"
printf 'def create_order(customer_id):\n    return {"customer_id": customer_id}\n' > src/orders/service.py
printf 'def post_orders(body):\n    return create_order(body["customer_id"])\n' > src/orders/api.py
printf 'from orders.service import create_order\n\ndef test_create_order():\n    assert create_order(1) == {"customer_id": 1}\n' > tests/orders/test_service.py
commit "feat(orders): service, api and tests"
printf '# Orders\n\nPOST /orders creates an order for a customer.\n' > docs/orders.md
commit "docs: orders"
git push -q -u origin feature/orders
git pack-refs --all

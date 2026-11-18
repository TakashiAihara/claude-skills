#!/usr/bin/env bash
# main ships Order{order_id, customer_id, Legacy_Note, nickname} and a Channel enum (both with
# pre-existing violations). feature/payment-status drops nickname without reserved, adds an enum
# without UNSPECIFIED, adds an RPC with off-convention names and a singular repeated field.
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

mkdir -p proto/shop/v1 docs/design
cat > proto/shop/v1/order.proto <<'PROTO'
syntax = "proto3";

package shop.v1;

service OrderService {
  rpc GetOrder(GetOrderRequest) returns (GetOrderResponse);
}

message GetOrderRequest {
  string order_id = 1;
}

message GetOrderResponse {
  Order order = 1;
}

message Order {
  string order_id = 1;
  string customer_id = 2;
  string Legacy_Note = 3;
  string nickname = 4;
}

enum Channel {
  WEB = 0;
  MOBILE = 1;
}
PROTO
cat > docs/design/payment-status.md <<'MD'
# Payment status

Orders expose a payment status so clients can show whether an order is paid.

- Enum `PaymentStatus` with values `PAYMENT_STATUS_UNSPECIFIED`, `PAYMENT_STATUS_PENDING`, `PAYMENT_STATUS_PAID` and `PAYMENT_STATUS_REFUNDED`
- Field `payment_status` on `Order`
- Field `tags` (repeated string) on `Order` for free-form labels
- RPC `ListOrders` returning the orders of a customer
MD
printf '# shop\n' > README.md
commit "feat: order service protos"
git push -q -u origin main
git remote set-head origin main

git switch -q -c feature/payment-status
cat > proto/shop/v1/order.proto <<'PROTO'
syntax = "proto3";

package shop.v1;

service OrderService {
  rpc GetOrder(GetOrderRequest) returns (GetOrderResponse);
  rpc ListOrders(ListOrdersParams) returns (Orders);
}

message GetOrderRequest {
  string order_id = 1;
}

message GetOrderResponse {
  Order order = 1;
}

message ListOrdersParams {
  string customer_id = 1;
}

message Orders {
  repeated Order orders = 1;
}

message Order {
  string order_id = 1;
  string customer_id = 2;
  string Legacy_Note = 3;
  PaymentStatus payment_status = 5;
  repeated string tag = 6;
}

enum Channel {
  WEB = 0;
  MOBILE = 1;
}

enum PaymentStatus {
  PENDING = 0;
  PAID = 1;
}
PROTO
commit "feat: payment status and ListOrders"
git push -q -u origin feature/payment-status
git pack-refs --all

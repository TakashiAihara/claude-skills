#!/usr/bin/env bash
# order-service: DynamoDB orders (caller-supplied address and notes, expires_at without TTL enabled),
# an uploads bucket, an ALB with access logs, and an audit_events table that only the code writes.
set -eu
export GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
git init -q -b main .
git config user.name dev
git config user.email dev@example.com
git config commit.gpgsign false

mkdir -p infra src/handlers src/repo
cat > infra/main.tf <<'TF'
resource "aws_dynamodb_table" "orders" {
  name         = "orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }
}

resource "aws_s3_bucket" "uploads" {
  bucket = "order-service-uploads"
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "expire-uploads"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

resource "aws_lb" "api" {
  name               = "order-service-api"
  load_balancer_type = "application"

  access_logs {
    bucket  = "order-service-alb-logs"
    enabled = true
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/order-service/app"
  retention_in_days = 90
}
TF
cat > src/types.ts <<'TS'
export type Order = {
  orderId: string
  customerEmail: string
  shippingAddress: string
  notes: string
  expiresAt: number
}

export type AuditEvent = {
  eventId: string
  orderId: string
  ip: string
  userAgent: string
  at: string
}
TS
cat > src/repo/orders.ts <<'TS'
import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb'
import type { Order } from '../types'

const client = new DynamoDBClient({})

export async function putOrder(order: Order) {
  await client.send(
    new PutItemCommand({
      TableName: 'orders',
      Item: {
        order_id: { S: order.orderId },
        customer_email: { S: order.customerEmail },
        shipping_address: { S: order.shippingAddress },
        notes: { S: order.notes },
        expires_at: { N: String(order.expiresAt) },
      },
    }),
  )
}
TS
cat > src/handlers/create.ts <<'TS'
import { logger } from '../logger'
import { putOrder } from '../repo/orders'

export async function createOrder(req: { headers: Record<string, string>; body: Record<string, string> }) {
  const { orderId, customerEmail, shippingAddress, notes } = req.body
  logger.info('create order', { email: customerEmail, ip: req.headers['x-forwarded-for'] })
  await putOrder({ orderId, customerEmail, shippingAddress, notes, expiresAt: Date.now() / 1000 + 86400 * 365 })
  return { orderId }
}
TS
cat > src/handlers/audit.ts <<'TS'
import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb'
import type { AuditEvent } from '../types'

const client = new DynamoDBClient({})

export async function recordAudit(e: AuditEvent) {
  await client.send(
    new PutItemCommand({
      TableName: 'audit_events',
      Item: {
        event_id: { S: e.eventId },
        order_id: { S: e.orderId },
        ip: { S: e.ip },
        user_agent: { S: e.userAgent },
        at: { S: e.at },
      },
    }),
  )
}
TS
printf 'export const logger = { info: (m: string, f?: object) => console.log(m, f) }\n' > src/logger.ts
printf '# order-service\n\nCreates orders for storefront callers.\n' > README.md
git add -A && git commit -q -m "feat: order service"

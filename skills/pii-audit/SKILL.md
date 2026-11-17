---
name: pii-audit
description: "Exhaustively investigate the personal information stored in a repository's data stores and write a personal-information.md inventory, classified from the APPI and GDPR viewpoints, separating what the service actively collects from what comes from the client. Use for a PII inventory or personal information audit. Triggers: PII audit, personal information audit, PII 棚卸し, 個人情報調査."
---

# PII Audit

Exhaustively investigate the personal information stored in each data store of a repository, and write an inventory document in the `personal-information.md` format.

## What to investigate

### Enumerate data stores

Enumerate the data stores from both the infra code (Terraform / CDK / k8s manifests) and the application code:

- RDB: RDS / Aurora / Cloud SQL / PostgreSQL / MySQL
- NoSQL: DynamoDB / Firestore / MongoDB
- KVS / Cache: ElastiCache / Redis / Memcached
- Queue: SQS / Kafka / Kinesis / Pub/Sub
- Object Storage: S3 / GCS / Athena / BigQuery
- Log: CloudWatch Logs / Datadog / Stackdriver / ALB access log
- Backup / Snapshot: PITR / RDS snapshot / S3 versioning

### Extract schemas

Check the data structure stored in each data store:

- The attribute / column definitions of Terraform resources such as `aws_dynamodb_table` and `aws_kinesis_firehose_delivery_stream`
- TypeScript / Go type definitions (`*.types.ts`, struct)
- The application's repository / mapper code (`PutCommand`, `INSERT`, `produce`, etc.)
- Glue catalog / schema registry definitions

### Classify PII categories

Classify the findings into these categories:

#### 1. Direct identifiers (direct PII)

- Name / email address / phone number / address / date of birth
- National ID number (such as My Number in Japan) / driver's license and other license numbers / passport number
- Individual identification codes (DNA, fingerprints, face photos, etc.)

#### 2. Personal-related information (APPI) / online identifiers (GDPR)

- IP address
- Cookie ID / advertising ID
- User-Agent
- Referer
- Device fingerprint

#### 3. Quasi-identifiers

- Cannot identify a person alone but can in combination
- Gender / date of birth / postal code / UA / Referer
- A judgment on ease of cross-referencing (容易照合性) is needed

#### 4. Sensitive information

- Health information / political opinions / sexual orientation / religious belief, etc.

### Draw the line of responsibility

Draw the line by who is responsible:

- Actively collected: what the service actively obtains from HTTP requests / headers / credentials -> within the service's responsibility
- Client-originated: free-format data passed in by the client (URL query / metadata / arbitrary JSON) -> within the client's responsibility (for an internal product, leave it to the caller)

This split makes explicit which PII the service itself must take responsibility for.

### Supplementary items

- Retention period / TTL: lifecycle policy / TTL attribute / message retention period
- Encryption: SSE / CMK / TLS
- Deletion operations: whether there is periodic deletion, manual vs automatic
- Data provided to clients: yes / no (distinguish operational data from provided data)
- Provision to third parties: directly tied to the consent obligation under APPI

## Output format

Write `personal-information.md` with this structure:

```markdown
# Premises

- Information as of YYYY/MM/DD
- Versions
    - <service name>: <version>

# Summary

The list of data recognized as personal information or equivalent. See each service section for details.

## <service name>

- **<PII data name>**
    - <where it is held> (retention period / deletion operations)

# <service name>

## <data store type>

### N. <table / resource name>

- Whether there is data equivalent to personal information that is actively collected
- Items held: a / b / c
- Whether the contents are the client's responsibility
- Encryption and backup settings
- Lifecycle / TTL
- Whether data is provided to clients
```

## Workflow

### 1. Understand the repository

```bash
# List the data store resources defined in Terraform
find infrastructure -name "*.tf" | xargs grep -l "aws_dynamodb_table\|aws_db_instance\|aws_elasticache\|aws_s3_bucket\|aws_kinesis\|aws_sqs"

# Schema definitions on the application side
find apps packages -name "*.types.ts" -o -name "*.entity.ts" -o -name "schema.ts"
```

### 2. Check the schemas

Read the schema and attributes of each data store, and list the data items that are stored.

### 3. Judge PII

Classify each item as direct PII / personal-related information / quasi-identifier / sensitive information / non-PII. Also separate client-originated data from actively collected data.

### 4. Confirm the legal viewpoint

- Domestic use only (APPI, Japan's Act on the Protection of Personal Information): judge by the concepts of "ease of cross-referencing" (容易照合性) and "personal-related information"
- Used in the EU (GDPR): treat all online identifiers as personal data

Confirm the scope of use with the user before judging.

### 5. Check the logs

Check that PII is not written to CloudWatch Logs / Firehose logs / ALB access logs, etc.:

```bash
grep -rn "logger\.\|Logger\|console\." apps/<service>/src --include="*.ts" | grep -v ".spec.ts"
```

Check that request bodies / headers / URLs are not logged directly.

### 6. Output

Generate `personal-information.md` in the format above. Use a two-level structure of summary and details.

## Cautions

- Use the term "personal information" strictly: under APPI, "personal information", "personal-related information" and "quasi-identifiers" are different concepts. Do not conflate them
- Do not guess the contents of client-originated data: state only that "personal information may be included, but it is the client's responsibility"
- Watch for missing TTL / lifecycle settings in Terraform: even if a type definition has a TTL attribute such as `expired`, the data is not deleted automatically unless Terraform has a `ttl` block. Check that the implementation and the infra are consistent
- Also check the ALB access log / CloudFront access log settings: load-balancer-level logs are in scope, not just application logs
- Confirm whether the document is throwaway or permanent: an inventory memo is often written as throwaway. Ask the user about its purpose before deciding the granularity

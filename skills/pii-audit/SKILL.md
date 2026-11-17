---
name: pii-audit
description: "Exhaustively investigate the personal information stored in a repository's data stores and write a personal-information.md inventory classified from the APPI and GDPR viewpoints, recording the origin of each item (actively collected or caller-supplied) separately from who is legally responsible. Use when asked for a PII inventory or personal information audit of a service. Triggers: PII audit, personal information audit, PII 棚卸し, 個人情報調査."
---

# PII Audit

Investigate the personal information held in each data store of a repository and write an inventory document in the `personal-information.md` format.

Requirements: `git` and a checkout of the repository (application code and infra code). This skill produces an engineering inventory, not legal advice: where a legal role or obligation is open, record it as open and send it to the statute or legal counsel.

## Step 0. Ask before investigating

Ask the user these three questions first, and do not investigate until they are answered:

- Scope of use: Japan only (APPI), used in the EU (GDPR), or both
- Purpose of the document: throwaway or permanent (decides the granularity)
- Output path of `personal-information.md`

## What to investigate

### Enumerate data stores

Enumerate the data stores from both the infra code (Terraform / CDK / k8s manifests) and the application code:

- RDB: RDS / Aurora / Cloud SQL / PostgreSQL / MySQL
- NoSQL: DynamoDB / Firestore / MongoDB
- KVS / Cache: ElastiCache / Redis / Memcached
- Queue / stream: SQS / Kafka / Pub/Sub
- Object storage: S3 / GCS
- Query engines over stored data: record the underlying store
- Log pipelines: application logs, log delivery streams, load balancer and CDN access logs
- Backup / snapshot: PITR / RDS snapshot / S3 versioning

### Extract schemas

Check the data structure stored in each data store:

- The attribute / column definitions of each table / stream / bucket resource in the infra code
- Type definitions in the application code (TypeScript types, Go structs, ORM entities)
- The application's repository / mapper code (inserts, puts, queue producers)
- Schema catalog / registry definitions

### Classify PII categories

Record two separate attributes per item: identifiability (categories 1-3) and sensitivity (category 4). An item can have both, for example a face photo used for identification is a direct identifier and also sensitive. For identifiability pick the single category that fits the item alone; use quasi-identifiers only for items that identify a person only in combination.

#### 1. Direct identifiers

- Name / email address / phone number / address / date of birth
- National ID number (such as My Number in Japan) / license numbers / passport number
- Individual identification codes (DNA, fingerprints, face photos, etc.)

#### 2. Personal-related information (APPI) / online identifiers (GDPR)

- IP address
- Cookie ID / advertising ID
- User-Agent / Referer
- Device fingerprint

#### 3. Quasi-identifiers

- Cannot identify a person alone but can in combination: gender / postal code / age band / other coarse attributes
- A judgment on ease of cross-referencing (容易照合性) is needed

#### 4. Sensitivity (second attribute, not an alternative to 1-3)

The two regimes have different lists; do not map one onto the other by name.

- GDPR special categories (Art. 9(1)): racial or ethnic origin, political opinions, religious or philosophical beliefs, trade union membership, genetic data, biometric data for the purpose of uniquely identifying a natural person, data concerning health, data concerning a natural person's sex life or sexual orientation
- APPI 要配慮個人情報 (Art. 2(3), Cabinet order, PPC guidelines 2-3): race, creed, social status, medical history, criminal record, the fact of having been harmed by a crime, disability, results of health checks, medical guidance or treatment, criminal procedures against the person, juvenile protection proceedings. Check the current statute and the PPC guidelines before relying on this list

### Record origin, then decide responsibility separately

Origin and legal responsibility are different questions. Do not answer the second with the first.

1. Record the origin of each item:
   - Actively collected: data the service itself obtains, generates or derives (for example from requests, headers or credentials)
   - Caller-supplied: free-form fields that callers pass in and the service stores as-is
2. Mark every caller-supplied store as in scope of the audit. Data that sits in the service's stores is inventoried whoever supplied it.
3. Record the legal role as "to be decided", and decide it from the processing purpose and the contracts, not from the origin:
   - GDPR: controller and processor are functional roles that follow the actual activities of the parties, not a label (EDPB Guidelines 07/2020 on the concepts of controller and processor, para. 12). A provider that stores data only on behalf of its customers and on their instructions is generally a processor (the guidelines' standardised cloud storage example). A processor has its own obligations, for example processing only on documented instructions, security measures under Art. 32, assisting with data subject requests, deleting or returning data at the end of the service, authorization for sub-processors, and notifying the controller of a breach without undue delay (Art. 28(2), 28(3), 33(2)). A service that decides its own purposes for the data (analytics, for example) may be a controller for that data
   - APPI: the PPC Q&A on cloud services treats whether the provider handles personal data as the test, not whether the stored data happens to include personal data. The business that holds the data has safety management duties (Art. 23). Whether the service is itself such a business, or only a provider that does not handle the data, depends on its access and contract. Confirm with the PPC guidelines and Q&A
4. Where the role is unclear, write "role: open, check with the statute / legal counsel". Never write "the caller's responsibility" as a conclusion.

### Supplementary items

- Retention period / TTL: lifecycle policy / TTL attribute / message retention period
- Encryption: SSE / CMK / TLS
- Deletion operations: whether there is periodic deletion, manual vs automatic
- Data returned to callers: yes / no (distinguish operational data from provided data)
- Provision to third parties: under APPI this ties to the consent requirement for third-party provision (Art. 27)

## Output format

Write `personal-information.md` with this structure:

```markdown
# Premises

- Information as of YYYY/MM/DD
- Scope of use: Japan / EU / both
- Versions
    - <service name>: <version>

# Summary

The list of data recognized as personal information or equivalent. See the details for each item.

## <service name>

- **<PII data name>**
    - <where it is held> (retention period / deletion operations)

# Details

## <service name>

### <data store type>

#### N. <table / resource name>

- Items held: a / b / c
- Identifiability, sensitivity and origin per item (actively collected / caller-supplied)
- Legal role: decided (controller / processor / not handling) or open, with the basis
- Encryption and backup settings
- Lifecycle / TTL
- Whether data is returned to callers
```

Example entry:

```markdown
#### 1. orders (DynamoDB)

- Items held: order_id / customer_email / shipping_address / health_note / notes
- customer_email: direct identifier, not sensitive, actively collected (taken from the auth token)
- shipping_address: direct identifier, not sensitive, caller-supplied (stored as-is from the request body)
- health_note: quasi-identifier, sensitive (health data), caller-supplied
- notes: free-form text, caller-supplied; personal information may be included
- Legal role: open for shipping_address and notes (service stores them for the caller; processor or controller to be decided from the contract), check with legal counsel
- Encryption and backup: SSE with AWS-managed key, PITR on
- Lifecycle / TTL: the setting found in the infra code, or "none found"
- Returned to callers: yes (all items)
```

## Workflow

Adapt the paths and patterns below to the stack. They are examples, not a layout the repository must have.

### 1. Understand the repository

```bash
# Data store resources in infra code (extend the pattern for the clouds in use)
git grep -lE 'aws_(dynamodb_table|db_instance|rds_cluster|elasticache|s3_bucket|kinesis|sqs_queue)|google_(sql_database_instance|storage_bucket|bigquery_dataset|pubsub_topic)'

# The same in CDK (TypeScript)
git grep -lE 'new (s3\.Bucket|dynamodb\.(Table|TableV2)|sqs\.Queue|rds\.(DatabaseInstance|DatabaseCluster))\('

# Schema definitions on the application side (extend for the ORM and language in use)
git grep -lE 'CREATE TABLE|@Entity|^model [A-Z]|z\.object|BaseModel|type [A-Z][A-Za-z]+ struct'
```

### 2. Check the schemas

Read the schema and attributes of each data store, and list the data items that are stored.

### 3. Reconcile the two lists

Compare the stores found from infra code with the stores found from application code. A store found by only one side (a table the code writes but no Terraform defines, a bucket Terraform defines but no code references) must be resolved or listed as unverified before the inventory is written.

### 4. Judge PII

Record each item's identifiability and sensitivity, record its origin, and set the legal role as decided or open (see "Record origin, then decide responsibility separately").

### 5. Confirm the legal viewpoint

- Domestic use only (APPI): judge by "ease of cross-referencing" (容易照合性, the state in which information can be easily collated with other information by the business's ordinary methods) and by "personal-related information" (information about a living individual that is not personal information, pseudonymized information or anonymized information)
- Used in the EU (GDPR): an online identifier is named in the definition of personal data (Art. 4(1)); treat IP addresses, cookie IDs and device identifiers as personal data

Use the scope the user gave in step 0.

### 6. Check the logs

Check that PII is not written to application logs, log delivery streams, or load-balancer and CDN access logs. Grep for logging of request bodies, headers, source IP, User-Agent and email, not for every logger call:

```bash
git grep -nIiE '(log|logger|console|print)[A-Za-z_.]*\(.*(body|headers|remote_?addr|\bip\b|user-?agent|x-forwarded-for|email)'
```

Also check the access log settings of the load balancer and CDN in the infra code: those logs are in scope, not just application logs.

### 7. Output

Generate `personal-information.md` at the path from step 0 in the format above. Use the two-part structure of summary and details.

## Cautions

- Use the term "personal information" strictly: under APPI, "personal information", "personal-related information" and "quasi-identifiers" are different concepts. Do not conflate them
- Do not guess the contents of caller-supplied data: state that personal information may be included, record the origin, and leave the legal role open unless the contract decides it
- Watch for missing TTL / lifecycle settings in the infra code: even if a type definition has a TTL-like attribute, the data is not deleted automatically unless the infra code enables TTL / lifecycle on the resource. Check that the implementation and the infra are consistent

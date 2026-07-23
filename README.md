# Music Streaming ETL Pipeline with Terraform

A fully automated AWS ETL pipeline built with **Terraform**, **Amazon S3**, **AWS Glue**, **AWS Step Functions**, **AWS Lambda**, and **Amazon DynamoDB** for processing and analyzing music streaming data.

This project provisions the complete cloud infrastructure and deploys an end-to-end data pipeline that validates incoming streaming data, computes daily KPIs, stores analytical results in DynamoDB, and archives processed files.

---

## Architecture

```
                +------------------+
                |   Streaming CSVs |
                +---------+--------+
                          |
                          v
                Amazon S3 (raw/streams/)
                          |
                          v
              EventBridge (Object Created)
                          |
                          v
               AWS Step Functions
                          |
        +-----------------+----------------+
        |                 |                |
        v                 v                v
 Validate Inputs   Transform KPIs   Load DynamoDB
 (Glue Python)    (Glue PySpark)   (Glue Python)
                          |
                          v
                  AWS Lambda Archive
                          |
                          v
                  S3 archive folder

On failure at any state: EventBridge (execution status FAILED/TIMED_OUT/ABORTED) -> SNS -> email
```

---

## Features

* Infrastructure as Code (Terraform)
* Event-driven trigger: new files in `raw/streams/` start the pipeline automatically via EventBridge, no polling or fixed schedule
* Automated ETL orchestration with Step Functions
* Data validation using AWS Glue Python Shell
* KPI computation using AWS Glue PySpark
* DynamoDB storage for analytical queries
* Automated archival of processed files
* SNS email alerting on pipeline failure
* CloudWatch logging
* IAM roles and least privilege policies
* Sample datasets included

---

## AWS Resources Created

### Amazon S3

Creates a private bucket with the following structure:

```
raw/
├── reference/
│   ├── songs.csv
│   └── users.csv
└── streams/
    ├── streams1.csv
    ├── streams2.csv
    └── streams3.csv

processed/
├── events/              # cumulative cleaned stream events (parquet, partitioned by source file)
├── genre_daily_kpis/    # recomputed KPI output loaded into DynamoDB
├── top_songs/
└── top_genres/
archive/                 # processed stream files moved here per execution
scripts/                 # Glue job scripts
tmp/                     # Glue temp/spill
```

---

### AWS Glue Jobs

| Job             | Purpose                    |
| --------------- | -------------------------- |
| Validate Inputs | Validate incoming datasets |
| Transform KPIs  | Compute daily metrics      |
| Load DynamoDB   | Load processed results     |

---

### DynamoDB Tables

| Table            | Description                                             |
| ---------------- | -------------------------------------------------------- |
| genre_daily_kpis | Daily genre statistics                                    |
| top_songs        | Top N songs per genre per day (`top_n_songs`, default 3)  |
| top_genres       | Top N genres per day (`top_n_genres`, default 5)          |
| pipeline_lock    | Single-writer lock that serializes pipeline executions    |

---

### Step Functions Workflow

The pipeline executes the following stages:

1. AcquireLock — takes a single-writer lock so runs never overlap (see [Concurrency Control](#concurrency-control))
2. ValidateInputs
3. TransformKPIs
4. LoadDynamoDB
5. ArchiveProcessedFiles
6. ReleaseLock — releases the lock on both success and failure paths

---

### Trigger

An S3 EventBridge notification fires an `Object Created` event whenever a file lands under `raw/streams/`. An EventBridge rule matches that event and starts the Step Functions execution directly — no manual invocation or polling required.

### Alerting

A second EventBridge rule watches the state machine's execution status. If an execution reaches `FAILED`, `TIMED_OUT`, or `ABORTED`, it publishes to the `<project_name>-alerts` SNS topic. Set `alert_email` in `terraform.tfvars` to subscribe an inbox (subscription must be confirmed via the email AWS sends).

---

## Daily KPIs Computed

### Genre-Level KPIs

* Listen Count
* Unique Listeners
* Total Listening Time
* Average Listening Time per User
* Top 3 Songs per Genre per Day
* Top 5 Genres per Day

**Total Listening Time** is the sum of each played track's full `duration_ms` (the `streams` schema carries only a `listen_time` timestamp, not an actual play length), and **Average Listening Time per User** is that total divided by the day's unique listeners.

**Multi-batch correctness:** the transform job appends every cleaned batch into a cumulative, partitioned event store under `processed/events/` and recomputes KPIs across the *full* history each run. So when a single day's data arrives across several batches, unique listeners and the top-N rankings stay correct instead of being overwritten by the latest batch alone. Event partitions are keyed by source file, so a reprocessed file replaces its own partition rather than double-counting.

---

## Input Data Schema

### songs.csv

```text
track_id
track_name
duration_ms
track_genre
```

### users.csv

```text
user_id
user_name
user_age
user_country
created_at
```

### streams.csv

```text
user_id
track_id
listen_time
```

---

## Project Structure

One file per concern, so a reviewer can find any resource type without scanning a monolith:

```
music-streaming-etl-terraform/
│
├── data/                # sample songs/users/streams CSVs
├── examples/            # sample Step Functions start-execution payload
├── glue_scripts/        # validate_inputs.py, transform_kpis.py, load_to_dynamodb.py
├── lambda/              # archive_files.py
│
├── locals.tf            # shared naming/prefix locals - single source of truth
├── s3.tf                # data lake bucket, encryption, versioning, script/sample uploads
├── dynamodb.tf           # genre_daily_kpis / top_songs / top_genres tables
├── glue.tf              # validate / transform / load Glue jobs
├── iam.tf                # roles + least-privilege inline policies
├── lambda.tf             # archive Lambda function
├── step_functions.tf    # orchestration state machine
├── triggers.tf           # S3 -> EventBridge -> Step Functions auto-trigger
├── alerting.tf           # SNS + EventBridge failure alerting
├── logging.tf            # CloudWatch log groups
│
├── variables.tf
├── outputs.tf
├── providers.tf
├── versions.tf
└── README.md
```

No resource name, S3 prefix, or output-folder name is duplicated as an independent literal across files — `locals.tf` defines each one once, and both Terraform and the Glue/Lambda scripts consume it via job arguments (`--genre_kpis_prefix`, `--top_songs_prefix`, `--top_genres_prefix`, `--required_columns`, `--top_n_songs`, `--top_n_genres`).

---

## Prerequisites

* Terraform >= 1.4
* AWS CLI
* AWS Account
* IAM User with AdministratorAccess (for lab purposes)

---

## AWS CLI Configuration

```bash
aws configure
```

Provide:

```text
AWS Access Key ID
AWS Secret Access Key
Default region: us-east-1
Default output format: json
```

Verify:

```bash
aws sts get-caller-identity
```

---

## Deployment

Navigate to the repository:

```bash
cd music-streaming-etl-terraform
```

Create variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Deploy:

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

## Configuration

Key variables in `terraform.tfvars` (see `terraform.tfvars.example` for the full list):

| Variable                 | Default              | Purpose                                              |
| ------------------------ | -------------------- | ----------------------------------------------------- |
| `top_n_songs`             | `3`                  | Songs ranked per genre per day                        |
| `top_n_genres`            | `5`                  | Genres ranked per day                                  |
| `alert_email`             | `null`               | Subscribes an inbox to pipeline-failure SNS alerts     |
| `glue_worker_type`        | `"G.1X"`             | Worker type for the PySpark transform job              |
| `glue_number_of_workers`  | `2`                  | Worker count for the PySpark transform job              |
| `upload_sample_data`      | `true`               | Whether to seed `raw/` with the sample CSVs on apply    |

None of these are hardcoded in the Glue/Lambda scripts — they're resolved in Terraform and passed down as `default_arguments` / environment variables, so changing a ranking size or worker count never requires touching Python.

---

## Run the Pipeline

Once deployed, dropping a stream CSV into `raw/streams/` (e.g. `aws s3 cp streams4.csv s3://$(terraform output -raw s3_bucket)/raw/streams/`) triggers the pipeline automatically via EventBridge — no manual step required.

To start a run manually (useful for backfills or re-running after fixing bad data), use:

```bash
aws stepfunctions start-execution \
--state-machine-arn $(terraform output -raw state_machine_arn) \
--input file://examples/start-execution.json
```

---

## Sample DynamoDB Queries

### Daily Genre KPIs

```bash
aws dynamodb get-item \
--table-name music-streaming-etl-genre-daily-kpis \
--key '{"date_genre":{"S":"2024-06-25#acoustic"}}'
```

### Top Songs

```bash
aws dynamodb query \
--table-name music-streaming-etl-top-songs-per-genre-daily \
--key-condition-expression "date_genre = :dg" \
--expression-attribute-values '{":dg":{"S":"2024-06-25#acoustic"}}'
```

### Top Genres

```bash
aws dynamodb query \
--table-name music-streaming-etl-top-genres-daily \
--key-condition-expression "listen_date = :d" \
--expression-attribute-values '{":d":{"S":"2024-06-25"}}'
```

---

## Logging and Monitoring

* AWS CloudWatch Logs
* AWS Step Functions Execution History
* AWS Glue Job Monitoring
* Lambda Execution Logs

---

## Concurrency Control

Each execution reprocesses everything currently under `raw/streams/`, then archives it, so two overlapping executions would race over the same files. The state machine guards against this with a DynamoDB semaphore:

* **`AcquireLock`** — a conditional `PutItem` (`attribute_not_exists(LockName)`) against the `pipeline-lock` table. Only one execution can hold the `"pipeline"` lock item at a time.
* If a second stream file lands while a run is in flight, its execution's `AcquireLock` hits `ConditionalCheckFailedException` and **retries with exponential backoff** (up to ~30+ min, covering the Glue transform timeout) until the first run releases the lock, then processes whatever files remain.
* **`ReleaseLock`** deletes the lock item on the success path; **`ReleaseLockOnFailure`** does the same on every failure path before ending in `Fail`, so a failed run never leaves the lock held.

**Residual edge case:** if an execution is force-aborted (so neither release state runs), the lock item persists and later runs will wait, then fail (triggering the failure alert). Recover by deleting the stuck item:

```bash
aws dynamodb delete-item \
  --table-name music-streaming-etl-pipeline-lock \
  --key '{"LockName": {"S": "pipeline"}}'
```

---

## CI/CD (GitHub Actions)

Infrastructure is managed by **Terraform**; **GitHub Actions** runs it. State is stored remotely in S3 with DynamoDB locking so CI and local runs share one source of truth.

```
bootstrap/  ── run once, locally ──►  S3 state bucket + DynamoDB lock + GitHub OIDC provider + CI role
     │
     ▼
main config  ──►  backend "s3"  ◄── Actions assume the CI role via OIDC (no stored keys)
                         │
   Pull request ─────────┼──►  ci.yml : fmt → validate → plan (plan posted as PR comment)
   Merge to main ────────┴──►  cd.yml : apply  (paused by the `production` environment gate)
```

### One-time setup

1. **Create the backend + CI role** (uses local state, run once):
   ```bash
   cd bootstrap
   cp terraform.tfvars.example terraform.tfvars   # set github_repository = "owner/repo"
   terraform init
   terraform apply
   ```
   Note the three outputs: `state_bucket`, `lock_table`, `ci_role_arn`.

2. **Point the backend at those names** — edit [backend.hcl](backend.hcl) so `bucket` and `dynamodb_table` match the `state_bucket` / `lock_table` outputs (already pre-filled for this account).

3. **Migrate existing local state into S3** (from the repo root):
   ```bash
   terraform init -backend-config=backend.hcl -migrate-state
   ```
   Answer `yes` when it offers to copy the current state — your already-deployed resources are preserved.

4. **Configure GitHub** (repo *Settings*):
   - *Secrets and variables → Actions → Variables*: add repository variable `AWS_ROLE_ARN` = the `ci_role_arn` output.
   - *Environments*: create an environment named `production` and add yourself as a **required reviewer** (this is the approval gate before `apply`).

5. **Set the Terraform version** in both workflows (`TF_VERSION`) to match your local `terraform version`, so CI reads the state file without a version-compatibility error.

That's it — open a PR to see `plan`, merge to run `apply` (after approval).

### No-OIDC fallback

If the account can't create an IAM OIDC provider (some locked-down sandboxes), skip the OIDC parts of `bootstrap` and instead store `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (and `AWS_SESSION_TOKEN` for temporary creds) as GitHub **secrets**, then replace the `configure-aws-credentials` step's `role-to-assume` with those secrets. Less secure and needs rotation — prefer OIDC on a real account.

> **DCE sandbox caveat:** a disposable sandbox recycles the account, so the state bucket, OIDC provider, and CI role won't persist between sessions, and its hourly-rotating keys make the secret fallback impractical. This CI/CD setup is built for a **persistent** AWS account; use it there.

---

## Cleanup

To avoid AWS charges:

```bash
terraform destroy
```

Confirm by typing:

```text
yes
```

---

## Technologies Used

* Terraform
* Amazon S3
* AWS Glue
* AWS Step Functions
* AWS Lambda
* Amazon DynamoDB
* Python
* PySpark
* AWS IAM
* CloudWatch


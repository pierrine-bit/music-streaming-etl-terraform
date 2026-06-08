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
                    Amazon S3
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
```

---

## Features

* Infrastructure as Code (Terraform)
* Automated ETL orchestration with Step Functions
* Data validation using AWS Glue Python Shell
* KPI computation using AWS Glue PySpark
* DynamoDB storage for analytical queries
* Automated archival of processed files
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
archive/
scripts/
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

| Table            | Description            |
| ---------------- | ---------------------- |
| genre_daily_kpis | Daily genre statistics |
| top_songs        | Top 3 songs per genre  |
| top_genres       | Top 5 genres per day   |

---

### Step Functions Workflow

The pipeline executes the following stages:

1. ValidateInputs
2. TransformKPIs
3. LoadDynamoDB
4. ArchiveProcessedFiles

---

## Daily KPIs Computed

### Genre-Level KPIs

* Listen Count
* Unique Listeners
* Total Listening Time
* Average Listening Time per User
* Top 3 Songs per Genre per Day
* Top 5 Genres per Day

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

```
music_etl_terraform/
│
├── data/
├── examples/
├── glue_scripts/
├── lambda/
├── glue.tf
├── iam.tf
├── lambda.tf
├── main.tf
├── outputs.tf
├── providers.tf
├── step_functions.tf
├── variables.tf
├── versions.tf
└── README.md
```

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

Clone the repository:

```bash
git clone https://github.com/your-username/music-etl-terraform.git

cd music-etl-terraform
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

## Run the Pipeline

Start the Step Functions execution:

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

---

## Author

**Damas Niyonkuru**

Data Engineer 

---

## License

This project was developed for educational and learning purposes.

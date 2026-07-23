# Remote state in S3 with DynamoDB locking. Values are supplied at init time
# from backend.hcl so this block stays account-agnostic:
#   terraform init -backend-config=backend.hcl
# The bucket and lock table are created once by the ../bootstrap configuration.
terraform {
  backend "s3" {}
}

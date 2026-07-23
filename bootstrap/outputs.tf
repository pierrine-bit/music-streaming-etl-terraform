output "state_bucket" {
  description = "Set this as `bucket` in ../backend.hcl."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "Set this as `dynamodb_table` in ../backend.hcl."
  value       = aws_dynamodb_table.lock.name
}

output "ci_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.ci.arn
}

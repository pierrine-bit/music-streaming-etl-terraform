variable "aws_region" {
  description = "Region for the state backend and CI role. Must match the main config's region."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix used for the state bucket, lock table, and CI role names. Must match the main config."
  type        = string
  default     = "music-streaming-etl"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI role, in 'owner/repo' form (e.g. amalitech/music-streaming-etl)."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform remote-state bucket. Leave null to derive one from project + account + region."
  type        = string
  default     = null
}

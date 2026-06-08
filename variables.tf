variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for resource names."
  type        = string
  default     = "music-streaming-etl"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name. Leave null to generate one from project_name and account id."
  type        = string
  default     = null
}

variable "upload_sample_data" {
  description = "Upload the provided local CSV files into the raw S3 prefixes."
  type        = bool
  default     = true
}

variable "local_data_dir" {
  description = "Local folder containing songs.csv, users.csv, streams1.csv, streams2.csv, streams3.csv."
  type        = string
  default     = "./data"
}

variable "glue_worker_type" {
  description = "Glue worker type for the PySpark transformation job."
  type        = string
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "Number of workers for the PySpark transformation job."
  type        = number
  default     = 2
}

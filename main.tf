locals {
  bucket_name = coalesce(var.bucket_name, "${var.project_name}-${data.aws_caller_identity.current.account_id}-${var.aws_region}")

  raw_prefix       = "raw"
  streams_prefix   = "raw/streams"
  songs_key        = "raw/reference/songs.csv"
  users_key        = "raw/reference/users.csv"
  processed_prefix = "processed"
  archive_prefix   = "archive"
  scripts_prefix   = "scripts"

  common_tags = {
    Project = var.project_name
    Managed = "terraform"
  }
}

resource "aws_s3_bucket" "pipeline" {
  bucket        = local.bucket_name
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "pipeline" {
  bucket                  = aws_s3_bucket.pipeline.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "glue_validation_script" {
  bucket = aws_s3_bucket.pipeline.id
  key    = "${local.scripts_prefix}/validate_inputs.py"
  source = "${path.module}/glue_scripts/validate_inputs.py"
  etag   = filemd5("${path.module}/glue_scripts/validate_inputs.py")
}

resource "aws_s3_object" "glue_transform_script" {
  bucket = aws_s3_bucket.pipeline.id
  key    = "${local.scripts_prefix}/transform_kpis.py"
  source = "${path.module}/glue_scripts/transform_kpis.py"
  etag   = filemd5("${path.module}/glue_scripts/transform_kpis.py")
}

resource "aws_s3_object" "glue_load_script" {
  bucket = aws_s3_bucket.pipeline.id
  key    = "${local.scripts_prefix}/load_to_dynamodb.py"
  source = "${path.module}/glue_scripts/load_to_dynamodb.py"
  etag   = filemd5("${path.module}/glue_scripts/load_to_dynamodb.py")
}

resource "aws_s3_object" "songs" {
  count  = var.upload_sample_data ? 1 : 0
  bucket = aws_s3_bucket.pipeline.id
  key    = local.songs_key
  source = "${var.local_data_dir}/songs.csv"
  etag   = filemd5("${var.local_data_dir}/songs.csv")
}

resource "aws_s3_object" "users" {
  count  = var.upload_sample_data ? 1 : 0
  bucket = aws_s3_bucket.pipeline.id
  key    = local.users_key
  source = "${var.local_data_dir}/users.csv"
  etag   = filemd5("${var.local_data_dir}/users.csv")
}

resource "aws_s3_object" "streams" {
  for_each = var.upload_sample_data ? toset(["streams1.csv", "streams2.csv", "streams3.csv"]) : toset([])
  bucket   = aws_s3_bucket.pipeline.id
  key      = "${local.streams_prefix}/${each.value}"
  source   = "${var.local_data_dir}/${each.value}"
  etag     = filemd5("${var.local_data_dir}/${each.value}")
}

resource "aws_glue_catalog_database" "music" {
  name = replace(var.project_name, "-", "_")
}

resource "aws_dynamodb_table" "genre_daily_kpis" {
  name         = "${var.project_name}-genre-daily-kpis"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date_genre"

  attribute {
    name = "date_genre"
    type = "S"
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table" "top_songs" {
  name         = "${var.project_name}-top-songs-per-genre-daily"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date_genre"
  range_key    = "rank"

  attribute {
    name = "date_genre"
    type = "S"
  }

  attribute {
    name = "rank"
    type = "N"
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table" "top_genres" {
  name         = "${var.project_name}-top-genres-daily"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "listen_date"
  range_key    = "rank"

  attribute {
    name = "listen_date"
    type = "S"
  }

  attribute {
    name = "rank"
    type = "N"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "glue" {
  name              = "/aws-glue/${var.project_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/vendedlogs/states/${var.project_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

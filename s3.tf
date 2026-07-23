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

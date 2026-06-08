resource "aws_glue_job" "validate" {
  name     = "${var.project_name}-validate-inputs"
  role_arn = aws_iam_role.glue.arn
  glue_version = "4.0"
  max_retries  = 1
  timeout      = 10

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${aws_s3_bucket.pipeline.bucket}/${aws_s3_object.glue_validation_script.key}"
  }

  default_arguments = {
    "--bucket"         = aws_s3_bucket.pipeline.bucket
    "--streams_prefix" = local.streams_prefix
    "--songs_key"      = local.songs_key
    "--users_key"      = local.users_key
    "--TempDir"        = "s3://${aws_s3_bucket.pipeline.bucket}/tmp/"
  }

  tags = local.common_tags
}

resource "aws_glue_job" "transform" {
  name              = "${var.project_name}-transform-kpis"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "4.0"
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  max_retries       = 1
  timeout           = 30

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.pipeline.bucket}/${aws_s3_object.glue_transform_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--bucket"           = aws_s3_bucket.pipeline.bucket
    "--streams_prefix"   = local.streams_prefix
    "--songs_key"        = local.songs_key
    "--users_key"        = local.users_key
    "--processed_prefix" = local.processed_prefix
    "--TempDir"          = "s3://${aws_s3_bucket.pipeline.bucket}/tmp/"
    "--enable-metrics"   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
  }

  tags = local.common_tags
}

resource "aws_glue_job" "load" {
  name     = "${var.project_name}-load-dynamodb"
  role_arn = aws_iam_role.glue.arn
  glue_version = "4.0"
  max_retries  = 1
  timeout      = 15

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${aws_s3_bucket.pipeline.bucket}/${aws_s3_object.glue_load_script.key}"
  }

  default_arguments = {
    "--bucket"           = aws_s3_bucket.pipeline.bucket
    "--processed_prefix" = local.processed_prefix
    "--genre_table"      = aws_dynamodb_table.genre_daily_kpis.name
    "--top_songs_table"  = aws_dynamodb_table.top_songs.name
    "--top_genres_table" = aws_dynamodb_table.top_genres.name
    "--TempDir"          = "s3://${aws_s3_bucket.pipeline.bucket}/tmp/"
  }

  tags = local.common_tags
}

locals {
  bucket_name = coalesce(var.bucket_name, "${var.project_name}-${data.aws_caller_identity.current.account_id}-${var.aws_region}")

  raw_prefix       = "raw"
  reference_prefix = "${local.raw_prefix}/reference"
  streams_prefix   = "${local.raw_prefix}/streams"
  songs_key        = "${local.reference_prefix}/songs.csv"
  users_key        = "${local.reference_prefix}/users.csv"
  processed_prefix = "processed"
  archive_prefix   = "archive"
  scripts_prefix   = "scripts"
  tmp_prefix       = "tmp"

  # Single source of truth for the processed/ sub-folder names. Passed into
  # both the transform and load Glue jobs as arguments so the two scripts
  # never need to agree on a literal string independently.
  genre_kpis_subprefix = "genre_daily_kpis"
  top_songs_subprefix  = "top_songs"
  top_genres_subprefix = "top_genres"

  # Cumulative, partitioned store of cleaned stream events. The transform job
  # appends each batch here and recomputes KPIs across the full history, so a
  # day's metrics stay correct even when its data arrives in several batches.
  events_subprefix = "events"

  glue_temp_dir = "s3://${aws_s3_bucket.pipeline.bucket}/${local.tmp_prefix}/"

  # Merged into every Glue job's default_arguments so --TempDir is defined once.
  glue_common_args = {
    "--TempDir" = local.glue_temp_dir
  }

  # Required columns per dataset, fed to the validation Glue job as a --required_columns
  # argument so the validation schema can change without redeploying the script.
  required_columns = {
    songs   = ["track_id", "track_name", "duration_ms", "track_genre"]
    users   = ["user_id", "user_name", "user_age", "user_country", "created_at"]
    streams = ["user_id", "track_id", "listen_time"]
  }

  common_tags = {
    Project = var.project_name
    Managed = "terraform"
  }

  # Trust policy principals, keyed so a single for_each data source in iam.tf
  # can produce all four assume-role documents instead of one block each.
  iam_assume_role_services = {
    glue            = "glue.amazonaws.com"
    lambda          = "lambda.amazonaws.com"
    step_functions  = "states.amazonaws.com"
    eventbridge_sfn = "events.amazonaws.com"
  }
}

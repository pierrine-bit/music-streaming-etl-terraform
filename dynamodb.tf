resource "aws_dynamodb_table" "genre_daily_kpis" {
  name         = "${var.project_name}-genre-daily-kpis"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date_genre"

  attribute {
    name = "date_genre"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
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

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table" "pipeline_lock" {
  # checkov:skip=CKV_AWS_28:Ephemeral single-item lock — no data to back up
  name         = "${var.project_name}-pipeline-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockName"

  attribute {
    name = "LockName"
    type = "S"
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

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

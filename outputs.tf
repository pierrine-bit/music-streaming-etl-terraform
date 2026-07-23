output "s3_bucket" {
  value = aws_s3_bucket.pipeline.bucket
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "glue_jobs" {
  value = {
    validate  = aws_glue_job.validate.name
    transform = aws_glue_job.transform.name
    load      = aws_glue_job.load.name
  }
}

output "dynamodb_tables" {
  value = {
    genre_daily_kpis = aws_dynamodb_table.genre_daily_kpis.name
    top_songs        = aws_dynamodb_table.top_songs.name
    top_genres       = aws_dynamodb_table.top_genres.name
  }
}

output "pipeline_alerts_topic_arn" {
  value = aws_sns_topic.pipeline_alerts.arn
}

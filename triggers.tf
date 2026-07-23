resource "aws_s3_bucket_notification" "eventbridge" {
  bucket      = aws_s3_bucket.pipeline.id
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "new_stream_file" {
  name        = "${var.project_name}-new-stream-file"
  description = "Starts the ETL pipeline whenever a new stream batch file lands in raw/streams/"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.pipeline.bucket]
      }
      object = {
        key = [{
          prefix = "${local.streams_prefix}/"
        }]
      }
    }
  })

  tags = local.common_tags

  depends_on = [aws_s3_bucket_notification.eventbridge]
}

resource "aws_cloudwatch_event_target" "start_pipeline" {
  rule     = aws_cloudwatch_event_rule.new_stream_file.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.eventbridge_sfn.arn
}

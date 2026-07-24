resource "aws_sns_topic" "pipeline_alerts" {
  name              = "${var.project_name}-alerts"
  kms_master_key_id = "alias/aws/sns" # server-side encryption with the AWS-managed SNS key
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "pipeline_alerts_email" {
  count     = var.alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_event_rule" "pipeline_failed" {
  name        = "${var.project_name}-pipeline-failed"
  description = "Fires when the ETL state machine execution fails, times out, or aborts"

  event_pattern = jsonencode({
    source      = ["aws.states"]
    detail-type = ["Step Functions Execution Status Change"]
    detail = {
      status          = ["FAILED", "TIMED_OUT", "ABORTED"]
      stateMachineArn = [aws_sfn_state_machine.pipeline.arn]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "pipeline_failed_sns" {
  rule = aws_cloudwatch_event_rule.pipeline_failed.name
  arn  = aws_sns_topic.pipeline_alerts.arn
}

data "aws_iam_policy_document" "pipeline_alerts_topic" {
  statement {
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.pipeline_alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.pipeline_failed.arn]
    }
  }
}

resource "aws_sns_topic_policy" "pipeline_alerts" {
  arn    = aws_sns_topic.pipeline_alerts.arn
  policy = data.aws_iam_policy_document.pipeline_alerts_topic.json
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project_name}-state-machine"
  role_arn = aws_iam_role.step_functions.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  definition = jsonencode({
    Comment = "S3 to Glue to DynamoDB music streaming ETL pipeline"
    StartAt = "AcquireLock"
    States = {
      # Serializes executions. Each run reprocesses everything under raw/streams/
      # and then archives it, so two overlapping runs would race over the same
      # files. A conditional PutItem grants the lock to one run at a time; a
      # second run that lands while the first is in flight retries (waits) until
      # the lock is released, then processes whatever files remain.
      AcquireLock = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:putItem"
        Parameters = {
          TableName           = aws_dynamodb_table.pipeline_lock.name
          ConditionExpression = "attribute_not_exists(LockName)"
          Item = {
            LockName      = { S = "pipeline" }
            "ExecutionId" = { "S.$" = "$$.Execution.Name" }
            "AcquiredAt"  = { "S.$" = "$$.State.EnteredTime" }
          }
        }
        Retry = [
          {
            # Another execution holds the lock: wait and retry. Sized to outlast
            # a full in-flight run (Glue transform timeout is 30 min). Both
            # spellings are listed because the SDK integration surfaces the
            # error as "DynamoDb.ConditionalCheckFailedException".
            ErrorEquals     = ["DynamoDb.ConditionalCheckFailedException", "DynamoDB.ConditionalCheckFailedException"]
            IntervalSeconds = 20
            BackoffRate     = 2
            MaxDelaySeconds = 60
            MaxAttempts     = 40
            JitterStrategy  = "FULL"
          },
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 5
            BackoffRate     = 2
            MaxAttempts     = 3
          }
        ]
        # Lock was never acquired here, so fail straight through without releasing.
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
        Next = "ValidateInputs"
      }
      ValidateInputs = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.validate.name
        }
        Retry = [{
          ErrorEquals     = ["Glue.AWSGlueException", "States.TaskFailed"]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "ReleaseLockOnFailure"
        }]
        Next = "TransformKPIs"
      }
      TransformKPIs = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.transform.name
        }
        Retry = [{
          ErrorEquals     = ["Glue.AWSGlueException", "States.TaskFailed"]
          IntervalSeconds = 60
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "ReleaseLockOnFailure"
        }]
        Next = "LoadDynamoDB"
      }
      LoadDynamoDB = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.load.name
        }
        Retry = [{
          ErrorEquals     = ["Glue.AWSGlueException", "States.TaskFailed"]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "ReleaseLockOnFailure"
        }]
        Next = "ArchiveProcessedFiles"
      }
      ArchiveProcessedFiles = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.archive.arn
          Payload = {
            bucket           = aws_s3_bucket.pipeline.bucket
            source_prefix    = local.streams_prefix
            archive_prefix   = local.archive_prefix
            "execution_id.$" = "$$.Execution.Name"
          }
        }
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "ReleaseLockOnFailure"
        }]
        Next = "ReleaseLock"
      }
      ReleaseLock = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:deleteItem"
        Parameters = {
          TableName = aws_dynamodb_table.pipeline_lock.name
          Key       = { LockName = { S = "pipeline" } }
        }
        Retry = [{
          ErrorEquals     = ["States.ALL"]
          IntervalSeconds = 5
          BackoffRate     = 2
          MaxAttempts     = 3
        }]
        Next = "PipelineSucceeded"
      }
      # Failure path: release the lock (so the next run isn't blocked) and still
      # end in a failed state so the failure alarm fires.
      ReleaseLockOnFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:deleteItem"
        Parameters = {
          TableName = aws_dynamodb_table.pipeline_lock.name
          Key       = { LockName = { S = "pipeline" } }
        }
        Retry = [{
          ErrorEquals     = ["States.ALL"]
          IntervalSeconds = 5
          BackoffRate     = 2
          MaxAttempts     = 3
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
        Next = "PipelineFailed"
      }
      PipelineSucceeded = {
        Type = "Succeed"
      }
      PipelineFailed = {
        Type  = "Fail"
        Cause = "Music streaming ETL pipeline failed. Check CloudWatch and Glue logs."
      }
    }
  })

  tags = local.common_tags
}

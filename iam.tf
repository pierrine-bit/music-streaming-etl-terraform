data "aws_iam_policy_document" "assume_role" {
  for_each = local.iam_assume_role_services

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = [each.value]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "${var.project_name}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role["glue"].json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "glue_inline" {
  statement {
    sid       = "ListPipelineBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.pipeline.arn]
    # No prefix condition: Spark lists/HEADs root-level directory markers
    # (e.g. "processed_$folder$") that a prefix-scoped condition would block.
  }

  statement {
    sid     = "ReadInputsAndScripts"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.pipeline.arn}/${local.reference_prefix}/*",
      "${aws_s3_bucket.pipeline.arn}/${local.streams_prefix}/*",
      "${aws_s3_bucket.pipeline.arn}/${local.scripts_prefix}/*",
    ]
  }

  statement {
    sid     = "ReadWriteWorkingData"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    # Whole-bucket object access (not just processed/* and tmp/*): Spark/Hadoop
    # writes zero-byte directory markers such as "processed_$folder$" at the
    # bucket root, which fall outside a "processed/*" prefix grant. This is a
    # single-purpose pipeline bucket, so granting object access across it is the
    # simplest correct scope and avoids marker-by-marker whack-a-mole.
    resources = ["${aws_s3_bucket.pipeline.arn}/*"]
  }

  statement {
    actions = ["dynamodb:BatchWriteItem", "dynamodb:PutItem", "dynamodb:DescribeTable"]
    resources = [
      aws_dynamodb_table.genre_daily_kpis.arn,
      aws_dynamodb_table.top_songs.arn,
      aws_dynamodb_table.top_genres.arn
    ]
  }

  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "glue_inline" {
  name   = "${var.project_name}-glue-inline"
  role   = aws_iam_role.glue.id
  policy = data.aws_iam_policy_document.glue_inline.json
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-archive-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role["lambda"].json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_s3" {
  statement {
    sid       = "ListPipelinePrefixes"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.pipeline.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "${local.streams_prefix}/*",
        "${local.archive_prefix}/*",
      ]
    }
  }

  statement {
    sid       = "ReadAndRemoveSource"
    actions   = ["s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.pipeline.arn}/${local.streams_prefix}/*"]
  }

  statement {
    sid       = "WriteArchive"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.pipeline.arn}/${local.archive_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "lambda_s3" {
  name   = "${var.project_name}-archive-lambda-s3"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_s3.json
}

resource "aws_iam_role" "step_functions" {
  name               = "${var.project_name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role["step_functions"].json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "step_functions_inline" {
  statement {
    actions = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
    resources = [
      aws_glue_job.validate.arn,
      aws_glue_job.transform.arn,
      aws_glue_job.load.arn
    ]
  }

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.archive.arn]
  }

  statement {
    sid       = "PipelineConcurrencyLock"
    actions   = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.pipeline_lock.arn]
  }

  statement {
    actions   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "step_functions_inline" {
  name   = "${var.project_name}-sfn-inline"
  role   = aws_iam_role.step_functions.id
  policy = data.aws_iam_policy_document.step_functions_inline.json
}

resource "aws_iam_role" "eventbridge_sfn" {
  name               = "${var.project_name}-eventbridge-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role["eventbridge_sfn"].json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "eventbridge_sfn_inline" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.pipeline.arn]
  }
}

resource "aws_iam_role_policy" "eventbridge_sfn_inline" {
  name   = "${var.project_name}-eventbridge-sfn-inline"
  role   = aws_iam_role.eventbridge_sfn.id
  policy = data.aws_iam_policy_document.eventbridge_sfn_inline.json
}

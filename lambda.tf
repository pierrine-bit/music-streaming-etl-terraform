data "archive_file" "archive_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/archive_files.py"
  output_path = "${path.module}/archive_files.zip"
}

resource "aws_lambda_function" "archive" {
  function_name    = "${var.project_name}-archive-processed-files"
  role             = aws_iam_role.lambda.arn
  handler          = "archive_files.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.archive_lambda.output_path
  source_code_hash = data.archive_file.archive_lambda.output_base64sha256
  timeout          = 120

  environment {
    variables = {
      BUCKET         = aws_s3_bucket.pipeline.bucket
      SOURCE_PREFIX  = local.streams_prefix
      ARCHIVE_PREFIX = local.archive_prefix
    }
  }

  tags = local.common_tags
}

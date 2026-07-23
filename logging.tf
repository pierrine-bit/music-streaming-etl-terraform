resource "aws_cloudwatch_log_group" "glue" {
  name              = "/aws-glue/${var.project_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/vendedlogs/states/${var.project_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

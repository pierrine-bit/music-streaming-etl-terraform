provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = coalesce(var.state_bucket_name, "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}")
  lock_table   = "${var.project_name}-tflock"
  ci_role_name = "${var.project_name}-github-actions"

  common_tags = {
    Project = var.project_name
    Managed = "terraform-bootstrap"
  }
}

# ---------------------------------------------------------------------------
# Remote state backend: versioned + encrypted S3 bucket and a DynamoDB lock
# table. The main configuration points its backend "s3" block at these.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# GitHub OIDC: lets Actions assume the CI role with a short-lived token
# instead of long-lived access keys stored as GitHub secrets. The provider is
# account-global (only one may exist per account), so we reference the existing
# one rather than creating it. Create it once with the AWS CLI if absent:
#   aws iam create-open-id-connect-provider \
#     --url https://token.actions.githubusercontent.com \
#     --client-id-list sts.amazonaws.com
# ---------------------------------------------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "ci_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only workflows in this repository (any branch/PR/environment) may assume it.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = local.ci_role_name
  assume_role_policy = data.aws_iam_policy_document.ci_assume_role.json
  tags               = local.common_tags
}

# Service-level permissions Terraform needs to manage the pipeline. PowerUser
# covers S3/DynamoDB/Glue/StepFunctions/Lambda/EventBridge/SNS/CloudWatch but
# excludes IAM, which the inline policy below grants (scoped to project roles).
resource "aws_iam_role_policy_attachment" "ci_poweruser" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "ci_iam" {
  # Manage the project's own service roles + inline/attached policies.
  statement {
    sid = "ManageProjectRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*"]
  }

  # Read-only lookups Terraform performs during plan/apply.
  statement {
    sid       = "ReadIamAndAccount"
    actions   = ["iam:GetRole", "iam:ListRoles", "iam:GetPolicy", "iam:GetPolicyVersion", "sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_iam" {
  name   = "${local.ci_role_name}-iam"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_iam.json
}

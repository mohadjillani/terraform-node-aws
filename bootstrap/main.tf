# Run once, by hand, before anything else.
#
# The state bucket cannot live in the state it stores: creating it with a
# backend configured means Terraform tries to read state from a bucket that
# does not exist yet. So this directory keeps its state locally, is applied
# once, and is then left alone.
#
#   cd bootstrap
#   terraform init && terraform apply
#
# It also creates the OIDC role CI assumes, so no long-lived AWS access keys
# ever exist.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "prefix" {
  description = "Bucket and table names are globally or account-unique; pick something of your own."
  type        = string
}

variable "github_repository" {
  description = "The repo allowed to assume the CI role, as owner/name."
  type        = string
  default     = "mohadjillani/terraform-node-aws"
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.prefix}-terraform-state"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    # State versioning is the only thing between a corrupted state file and
    # rebuilding an environment by hand.
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
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The lock table is what makes CI applies safe. Without it, two workflow runs
# starting seconds apart both plan against the same state and the second
# overwrites the first.
resource "aws_dynamodb_table" "locks" {
  name         = "${var.prefix}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---- OIDC federation for CI ------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  ci_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Scoped to this repository. Without the `sub` condition, any GitHub
        # Actions workflow in the world can assume this role — which is the
        # single most common OIDC misconfiguration.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role" "ci" {
  name               = "${var.prefix}-terraform-ci"
  assume_role_policy = local.ci_assume_role_policy
}

# Terraform needs broad permissions to create the stack, so this is deliberately
# an administrative role — and the `sub` condition above is what keeps it
# reachable only from this repository. A production account should narrow this
# to the services actually used.
resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "lock_table" {
  value = aws_dynamodb_table.locks.id
}

output "ci_role_arn" {
  description = "Set as the AWS_ROLE_ARN secret in the repository."
  value       = aws_iam_role.ci.arn
}

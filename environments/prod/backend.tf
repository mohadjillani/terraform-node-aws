# State lives in S3 with a DynamoDB lock table.
#
# The lock is what makes a CI apply safe: without it, two workflow runs that
# start within a few seconds of each other both plan against the same state and
# the second overwrites the first. The bucket and the table are created once by
# `bootstrap/`, which cannot itself live in the state it stores.
#
# Commented out because this repository has never been applied — an
# uncommented backend makes `terraform init` demand credentials, which would
# stop `terraform test` from running in CI. Uncomment and fill in the bucket
# name to use it.
#
# terraform {
#   backend "s3" {
#     bucket         = "REPLACE-terraform-state"
#     key            = "prod/terraform.tfstate"
#     region         = "eu-west-1"
#     dynamodb_table = "REPLACE-terraform-locks"
#     encrypt        = true
#   }
# }

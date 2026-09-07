mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

variables {
  prefix = "test"
}

run "the_state_bucket_is_private_and_versioned" {
  module {
    source = "./bootstrap"
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "The state bucket does not block public access — it contains every resource id and every output."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State versioning is off; a corrupted state file would be unrecoverable."
  }
}

# The single most common OIDC misconfiguration: without the `sub` condition,
# any GitHub Actions workflow anywhere can assume the role.
run "only_this_repository_can_assume_the_ci_role" {
  module {
    source = "./bootstrap"
  }

  assert {
    condition     = can(regex("repo:mohadjillani/terraform-node-aws:\\*", local.ci_assume_role_policy))
    error_message = "The CI role is not scoped to this repository."
  }

  assert {
    condition     = can(regex("token.actions.githubusercontent.com:aud", local.ci_assume_role_policy))
    error_message = "The trust policy does not check the audience claim."
  }
}

run "a_different_repository_is_refused" {
  module {
    source = "./bootstrap"
  }

  variables {
    github_repository = "someone-else/their-repo"
  }

  assert {
    condition     = !can(regex("repo:mohadjillani/terraform-node-aws", local.ci_assume_role_policy))
    error_message = "The trust policy still names the original repository."
  }
}

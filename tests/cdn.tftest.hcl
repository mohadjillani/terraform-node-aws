mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::test-assets"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/E123456789ABCD"
    }
  }
}

variables {
  name = "test"
}

run "the_bucket_blocks_public_access_four_ways" {
  module {
    source = "./modules/cdn"
  }

  # All four, explicitly. The bucket-level default has changed over the years,
  # so relying on it means the answer to "is this bucket public" depends on
  # when it was created.
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.assets.block_public_acls,
      aws_s3_bucket_public_access_block.assets.block_public_policy,
      aws_s3_bucket_public_access_block.assets.ignore_public_acls,
      aws_s3_bucket_public_access_block.assets.restrict_public_buckets,
    ])
    error_message = "The assets bucket does not block public access."
  }
}

run "only_this_distribution_can_read_the_bucket" {
  module {
    source = "./modules/cdn"
  }

  assert {
    condition     = can(regex("cloudfront.amazonaws.com", local.bucket_policy))
    error_message = "The bucket policy does not grant CloudFront."
  }

  # Without the source-ARN condition, any CloudFront distribution in any AWS
  # account can read the bucket.
  assert {
    condition     = can(regex("AWS:SourceArn", local.bucket_policy))
    error_message = "The bucket policy is not scoped to this distribution."
  }

  assert {
    condition     = !can(regex("\"Principal\":\\s*\"\\*\"", local.bucket_policy))
    error_message = "The bucket policy grants every principal."
  }
}

run "viewers_are_redirected_to_https" {
  module {
    source = "./modules/cdn"
  }

  assert {
    condition     = aws_cloudfront_distribution.assets.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "CloudFront serves the assets over plain HTTP."
  }

  assert {
    condition     = aws_cloudfront_distribution.assets.default_cache_behavior[0].compress
    error_message = "Compression is off, which is free bandwidth thrown away."
  }
}

run "the_origin_uses_access_control_not_a_public_bucket" {
  module {
    source = "./modules/cdn"
  }

  # `origin` is a set, so it has no addressable index — a `for` expression is
  # the only way to reach into one.
  assert {
    condition = alltrue([
      for origin in aws_cloudfront_distribution.assets.origin :
      origin.origin_access_control_id != "" && origin.origin_access_control_id != null
    ])
    error_message = "An origin is not using origin access control."
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.assets.signing_protocol == "sigv4"
    error_message = "Origin access control should sign with SigV4."
  }
}

run "a_deploy_can_be_rolled_back" {
  module {
    source = "./modules/cdn"
  }

  # A bad deploy overwrites the current object; the previous version is what a
  # rollback restores.
  assert {
    condition     = aws_s3_bucket_versioning.assets.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning is off, so an overwritten asset cannot be recovered."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.assets.rule) > 0
    error_message = "Old versions accumulate forever without a lifecycle rule."
  }
}

run "a_certificate_raises_the_minimum_tls_version" {
  module {
    source = "./modules/cdn"
  }

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
    aliases         = ["assets.example.com"]
  }

  assert {
    condition     = aws_cloudfront_distribution.assets.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    error_message = "The distribution allows a TLS version below 1.2."
  }

  assert {
    condition     = aws_cloudfront_distribution.assets.viewer_certificate[0].cloudfront_default_certificate == false
    error_message = "A custom certificate was given but the default is still in use."
  }
}

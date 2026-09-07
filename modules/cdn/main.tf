resource "aws_s3_bucket" "assets" {
  bucket = "${var.name}-assets"
  tags   = merge(var.tags, { Name = "${var.name}-assets" })

  lifecycle {
    # Built assets are replaceable, but the bucket name is not — a deleted
    # bucket name can be claimed by anyone, and every deployed page still
    # pointing at it then loads someone else's JavaScript.
    prevent_destroy = true
  }
}

# All four settings, explicitly. The bucket-level default has changed over the
# years and relying on it means the answer to "is this bucket public" depends on
# when it was created.
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    # A bad deploy overwrites the current object; the previous version is what
    # a rollback restores.
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      # Long enough to roll back, short enough that a year of deploys does not
      # accumulate silently on the bill.
      noncurrent_days = 30
    }
  }
}

# Origin access control, not the older origin access identity. OAI is
# deprecated and does not support SigV4 for newer regions.
resource "aws_cloudfront_origin_access_control" "assets" {
  name                              = "${var.name}-assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Built with `jsonencode` rather than `aws_iam_policy_document`, so
# `terraform test` can assert on what it actually grants — see the note in
# modules/service/main.tf.
locals {
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOnly"
      Effect    = "Allow"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.assets.arn}/*"
      Principal = { Service = "cloudfront.amazonaws.com" }
      # Scoped to this distribution. Without the condition, any CloudFront
      # distribution in any AWS account can read the bucket.
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.assets.arn }
      }
    }]
  })
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = local.bucket_policy
}

resource "aws_cloudfront_distribution" "assets" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = var.price_class
  aliases             = var.aliases

  origin {
    domain_name              = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id                = "assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }

  default_cache_behavior {
    target_origin_id       = "assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # CachingOptimized, AWS's managed policy. Content-hashed filenames make a
    # long TTL safe, and a purge is then never needed — the URL changes
    # instead.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # A single-page app: unknown paths are the client-side router's problem, not
  # a 404. Without this, a deep link reloaded in the browser returns S3's error
  # page.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.certificate_arn == null
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = var.certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.certificate_arn == null ? null : "TLSv1.2_2021"
  }

  tags = var.tags
}

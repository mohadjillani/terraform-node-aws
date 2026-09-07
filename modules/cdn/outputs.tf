output "bucket_name" {
  value = aws_s3_bucket.assets.id
}

output "distribution_domain_name" {
  value = aws_cloudfront_distribution.assets.domain_name
}

output "distribution_id" {
  description = "Needed by a deploy script that invalidates after uploading."
  value       = aws_cloudfront_distribution.assets.id
}

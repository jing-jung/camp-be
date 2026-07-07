output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "hosted_url" {
  description = "Full HTTPS URL for the frontend"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}
